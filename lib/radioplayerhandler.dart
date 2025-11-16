import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:grradio/radiostation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class RadioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  RadioStation? _currentStation;
  bool _isLoading = false;
  // 💡 NEW: State to track recording status
  bool _isRecording = false;
  String? _lastExtractedStreamUrl;

  // 💡 NEW: Dio components for stream recording
  final Dio _dio = Dio();
  CancelToken? _recordingCancelToken;

  final List<RadioStation> _radioStations;

  RadioPlayerHandler({required List<RadioStation> stations})
    : _radioStations = stations {
    _dio.options.receiveTimeout = const Duration(
      minutes: 5,
    ); // e.g., 5 minutes or more
    _dio.options.connectTimeout = const Duration(
      seconds: 15,
    ); // Ensure initial connection is good
    _setupAudioSession();
    _notifyAudioHandlerAboutPlaybackEvents();

    // Set up player event listeners
    _player.playerStateStream.listen((playerState) {
      _isLoading = playerState.processingState == ProcessingState.loading;
      _updatePlaybackState();
    });

    _player.processingStateStream.listen((processingState) {
      _isLoading = processingState == ProcessingState.loading;
      _updatePlaybackState();
    });
  }

  // 💡 NEW: Method to toggle recording state and handle simulation
  Future<void> toggleRecord(MediaItem? mediaItem) async {
    if (mediaItem == null || !playbackState.value.playing) {
      _sendPermissionDenied('Please play a radio station before recording.');
      return;
    }

    if (!_isRecording) {
      // 1. Request/Check Permissions before starting
      final status = await Permission.audio.request();

      if (status.isGranted || status.isLimited) {
        // Permission granted, start recording
        _isRecording = true;
        _sendRecordStatus(true);
        await _startRecording(mediaItem);
      } else {
        // Permission denied
        _sendPermissionDenied('Storage permission denied. Cannot record.');
        openAppSettings(); // Suggest opening settings
        return;
      }
    } else {
      // 2. Stop Recording
      await _stopRecording();
      _isRecording = false;
      _sendRecordStatus(false);
    }
  }

  Future<void> _startRecording(MediaItem mediaItem) async {
    _recordingCancelToken = CancelToken();
    String currentUrl =
        _currentStation?.streamUrl ??
        'Unknown streaming URL _currentStation.streamUrl';

    // Headers for network requests (used by both http and dio)
    const Map<String, String> richHeaders = {
      'User-Agent': 'Mozilla/5.0 (compatible; Flutter Radio Recorder)',
      'Referer': 'https://akashvani.gov.in/',
      'Accept-Encoding': 'identity',
      'Accept': '*/*',
    };

    // 💡 NEW: Flag to determine if we should use the HLS polling loop
    bool isHlsRecording = false;

    // 💡 CRITICAL FIX: Iteratively resolve M3U8 links until a direct audio stream is found
    int maxRedirects = 3; // Prevent infinite loops
    for (int i = 0; i < maxRedirects; i++) {
      if (currentUrl.toLowerCase().contains('.m3u8')) {
        print(
          'M3U8 detected. Attempting to extract direct stream URL for recording...',
        );

        final Uri baseUri = Uri.parse(currentUrl);

        try {
          final response = await http.get(baseUri, headers: richHeaders);

          if (response.statusCode == 200) {
            final lines = response.body.split('\n');
            String? foundUrl;

            for (final line in lines) {
              final trimmedLine = line.trim();
              // Skip comments and empty lines
              if (trimmedLine.isNotEmpty && !trimmedLine.startsWith('#')) {
                // Found a potential URL.
                String resolvedUrl = baseUri.resolve(trimmedLine).toString();

                // If it's another playlist, we'll try to follow it in the next loop iteration.
                if (resolvedUrl.toLowerCase().contains('.m3u8')) {
                  foundUrl = resolvedUrl;
                  print("Found secondary M3U8 playlist: $foundUrl");
                  break; // Follow this next
                } else {
                  // 💡 CRITICAL CHANGE: We found a media segment (.ts, .aac, etc.).
                  // This means the CURRENT URL (baseUri) is the bitrate-specific M3U8
                  // playlist we must use for continuous polling.
                  print(
                    "Media segment found. Will use current M3U8 for continuous recording.",
                  );
                  isHlsRecording = true;
                  i = maxRedirects; // Exit the outer loop
                  break; // Exit the inner lines loop
                }
              }
            }

            if (foundUrl != null) {
              currentUrl =
                  foundUrl; // Update to the new M3U8 URL (e.g., bitrate playlist)
            } else if (isHlsRecording) {
              // Segment found, currentUrl is the correct M3U8 URL. Break out.
              break;
            } else {
              // If the playlist was empty or just comments, stop trying to extract
              print(
                "M3U8 file was empty or contained no links. Stopping extraction.",
              );
              break;
            }
          } else {
            print(
              "Failed to download M3U8 playlist. Status: ${response.statusCode}",
            );
            break;
          }
        } catch (e) {
          print("Error during M3U8 extraction: $e. Using last known URL.");
          break;
        }
      } else {
        // Not an M3U8, so it's the direct stream URL we want to record.
        break;
      }
    }
    final recordingUrl =
        currentUrl; // This is either the direct stream OR the final M3U8 playlist URL.

    // --- 1. Determine File Path and Extension ---
    Directory directory;
    final externalDirectories = await getExternalStorageDirectories(
      type: StorageDirectory.downloads,
    );

    if (externalDirectories != null && externalDirectories.isNotEmpty) {
      directory = externalDirectories.first;
      print('Saving to Downloads directory: ${directory.path}');
    } else {
      // Fallback to internal app storage (Application Documents) if Downloads path is unavailable
      print(
        'Warning: Downloads directory unavailable, falling back to application documents.',
      );
      directory = await getApplicationDocumentsDirectory();
    }
    // 💡 REVISED PATH LOGIC: Attempt to target the public Downloads folder.

    // Ensure the directory exists
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    // Attempt to guess the file extension (MP3 is most common for streams)
    String extension = '.mp3';
    if (recordingUrl.toLowerCase().contains('.ts')) {
      extension = '.ts'; // Save as .ts (Transport Stream)
    } else if (recordingUrl.toLowerCase().contains('.aac') ||
        recordingUrl.toLowerCase().contains('.m4a')) {
      extension = '.aac';
    } else if (recordingUrl.toLowerCase().contains('.ogg')) {
      extension = '.ogg';
    }

    // Create a safe filename
    final safeTitle = mediaItem.title.replaceAll(RegExp(r'[^\w\s\-]'), '');
    final fileName =
        '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}$extension';
    final filePath = '${directory.path}/$fileName';

    print('Attempting to record stream from: $recordingUrl');
    print('Saving file to: $filePath');

    IOSink? sink;
    bool didError = false;
    final file = File(filePath);
    // 💡 NEW: Set to track segments already downloaded for HLS
    final Set<String> downloadedSegments = {};

    try {
      // 2. Open the file write stream (sink) in append mode
      sink = file.openWrite(mode: FileMode.append);

      // --- 2. HLS Polling Loop OR Direct Stream Download ---
      if (isHlsRecording) {
        // 💡 HLS Polling Logic: Loop until canceled
        while (!(_recordingCancelToken?.isCancelled ?? false)) {
          // 2.1. Fetch the M3U8 Playlist
          final playlistUri = Uri.parse(recordingUrl);
          final playlistResponse = await http.get(
            playlistUri,
            headers: richHeaders,
          );

          if (playlistResponse.statusCode != 200) {
            didError = true;
            throw Exception(
              'Failed to fetch M3U8 playlist: ${playlistResponse.statusCode}',
            );
          }

          final lines = playlistResponse.body.split('\n');
          final segmentUrls = <String>[];

          // 2.2. Parse M3U8 for new segments
          for (final line in lines) {
            final trimmedLine = line.trim();
            if (trimmedLine.isNotEmpty &&
                !trimmedLine.startsWith('#') &&
                !trimmedLine.toLowerCase().contains('.m3u8')) {
              // Resolve URL relative to the playlist URL
              final segmentUrl = playlistUri.resolve(trimmedLine).toString();
              segmentUrls.add(segmentUrl);
            }
          }

          // 2.3. Download and Append NEW Segments
          for (final segmentUrl in segmentUrls) {
            // Only download segments we haven't seen yet
            if (!downloadedSegments.contains(segmentUrl)) {
              print('Downloading new segment: ${segmentUrl.split('/').last}');

              if (_recordingCancelToken?.isCancelled == true || !_isRecording) {
                print(
                  'Segment download loop aborted due to user cancellation.',
                );
                // Use 'return;' or 'break;' here to exit the segment fetching function/loop immediately.
                return;
              }

              try {
                // Use Dio to download the single segment stream
                final segmentResponse = await _dio.get<ResponseBody>(
                  segmentUrl,
                  options: Options(
                    responseType: ResponseType.stream,
                    // Short timeout is fine for single segments, but set for safety
                    receiveTimeout: const Duration(seconds: 30),
                    headers: richHeaders,
                  ),
                  cancelToken: _recordingCancelToken,
                );
                print('Recording finished naturally and saved to: $filePath');
                if (segmentResponse.data?.stream != null) {
                  await sink.addStream(segmentResponse.data!.stream);
                  downloadedSegments.add(segmentUrl); // Mark as downloaded
                } else {
                  print('Error: Segment stream was null for $segmentUrl');
                }
              } on DioException catch (e) {
                // 💡 CRITICAL FIX 2: Catch the Dio cancellation error and do NOT treat it as a success.
                if (e.type == DioExceptionType.cancel) {
                  print(
                    'Recording segment fetch was intentionally cancelled by user.',
                  );
                  // Do nothing else here. The loop check (Fix 1) will prevent further execution.
                } else {
                  // Handle other network/Dio errors
                  print('Dio segment download error: $e');
                }
                // IMPORTANT: If an error or cancellation occurs, ensure the code that queues
                // the *next* segment is skipped. If this function is inside a `while(true)` loop,
                // use a `break;` or `return;` based on the error type if it's not a cancellation.
              } catch (e) {
                // Handle other errors (e.g., file system errors)
                print('General segment download error: $e');
              }
            }
          }

          // 2.4. Wait for the next segment to be published (usually 5-10 seconds)
          await Future.delayed(const Duration(seconds: 10));
        }
      } else {
        // 💡 Direct Stream Logic: Single Dio request for non-HLS streams
        final response = await _dio.get<ResponseBody>(
          recordingUrl,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(
              minutes: 30,
            ), // Long timeout for continuous stream
            headers: richHeaders,
          ),
          cancelToken: _recordingCancelToken,
        );
        print('Recording finished naturally and saved to: $filePath');
        print('Dio Response Status Code: ${response.statusCode}');

        if (response.data?.stream != null) {
          await sink.addStream(response.data!.stream);
          downloadedSegments.add(recordingUrl); // Mark as downloaded
        } else {
          print('Error: Segment stream was null for $recordingUrl');
        }
        // Listen to the network stream and pipe it to the file sink
        await sink.addStream(response.data!.stream);
      }

      // This line is reached when the stream ends (HLS loop canceled or direct stream finished)
      print('Recording finalized and saved successfully to: $filePath');
    } on DioException catch (e) {
      // 5. Handle errors and cancellations
      final isCancel = e.type == DioExceptionType.cancel;

      if (e.type == DioExceptionType.cancel) {
        print('Recording segment fetch was intentionally cancelled by user.');
        // Do not proceed with the next segment. The calling function should handle
        // the loop exit based on this exception or the status check (Fix 1).
      } else {
        // Handle other network/Dio errors
        print('Dio segment download error: $e');
      }

      if (!isCancel) {
        didError = true;
        final errorMessage =
            e.message ?? 'Unknown streaming error: ${e.toString()}';

        print('Recording Error: $errorMessage');
        // Assuming _sendPermissionDenied is a utility to notify the user/UI
        // You might rename this to something like _sendRecordingFailed
        _sendPermissionDenied('Recording failed: $errorMessage');
      }
    } finally {
      // 🚨 CRITICAL FIX 2: ALWAYS close the sink to flush data and finalize the file!
      if (sink != null) {
        await sink.close();
      }

      // 🚨 CRITICAL FIX 3: Delete the file if a non-cancellation error occurred
      // OR if it was canceled (as a canceled file is corrupt/partial).
      if (didError || (_recordingCancelToken?.isCancelled ?? false)) {
        if (await file.exists()) {
          await file.delete();
          print('Cleaned up partial/corrupt file: $filePath');
        }
      }
    }
  }

  Future<void> _stopRecording() async {
    print('Stopping recording...');

    // Cancels the Dio request, which gracefully stops the stream write.
    if (_recordingCancelToken != null && !_recordingCancelToken!.isCancelled) {
      // The cancel message is purely for logging/debugging purposes
      _recordingCancelToken!.cancel('Recording stopped by user');
      print('Dio download cancelled successfully.');
    }
    _recordingCancelToken?.cancel();
    _recordingCancelToken = null;
    // The UI handler will send the 'Recording saved' message upon receiving _sendRecordStatus(false)

    customEvent.add({'event': 'record_status', 'isRecording': false});
  }

  // Helper to send the custom event to the UI
  void _sendRecordStatus(bool isRecording) {
    customEvent.add({'event': 'record_status', 'isRecording': isRecording});
  }

  // Helper to send permission denied message
  void _sendPermissionDenied(String message) {
    customEvent.add({'event': 'permission_denied', 'message': message});
  }

  // Override to ensure recording stops when playback stops
  @override
  Future<void> stop() async {
    // 💡 NEW: Stop recording if playing stops
    if (_isRecording) {
      // Ensure we stop recording gracefully before player stops
      await _stopRecording();
      _isRecording = false;
      _sendRecordStatus(false);
    }

    await _player.stop();
    _currentStation = null;
    mediaItem.add(null);
  }

  @override
  Future<void> skipToNext() async {
    // Stop recording before changing station
    if (_isRecording) {
      await toggleRecord(mediaItem.value);
    }

    final currentIndex = _currentStation != null
        ? _radioStations.indexWhere(
            (station) =>
                station.id == (_currentStation?.id ?? 'Unknown Station ID'),
          )
        : -1;

    if (currentIndex != -1) {
      final nextIndex = (currentIndex + 1) % _radioStations.length;
      await _playStation(_radioStations[nextIndex]);
    } else if (_radioStations.isNotEmpty) {
      await _playStation(_radioStations.first);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    // Stop recording before changing station
    if (_isRecording) {
      await toggleRecord(mediaItem.value);
    }

    final currentIndex = _currentStation != null
        ? _radioStations.indexWhere(
            (station) =>
                station.id == (_currentStation?.id ?? 'Unknown Station ID'),
          )
        : -1;

    if (currentIndex != -1) {
      final prevIndex =
          (currentIndex - 1 + _radioStations.length) % _radioStations.length;
      await _playStation(_radioStations[prevIndex]);
    } else if (_radioStations.isNotEmpty) {
      await _playStation(_radioStations.last);
    }
  }

  // --- The rest of the methods remain unchanged ---
  Future<void> _setupAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(
      const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.allowBluetooth,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ),
    );
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      _updatePlaybackState();
    });
  }

  void _updatePlaybackState({
    // Use a default state to avoid accessing null properties if a value is not yet available
    PlaybackState? state,
  }) {
    final playing = _player.playing;

    final processingState = _player.processingState;

    // 1. Determine which controls are supported in the current state
    final controls = <MediaControl>[];

    // 1. Pause/Play Control: Must be present if media is loaded
    if (mediaItem.value != null) {
      if (playing) {
        controls.add(MediaControl.pause);
      } else {
        controls.add(MediaControl.play);
      }
    }

    // Include Next/Previous controls ONLY if you have multiple stations
    // You must access the list of stations that was passed to the handler's constructor.
    // Assuming you have a variable or way to access the total station count:
    // if (radioStations.length > 1) { // Replace radioStations with your actual list
    if (_radioStations.length > 1) {
      // They should be available regardless of current playing state
      controls.add(MediaControl.skipToPrevious);
      controls.add(MediaControl.skipToNext);
    }

    controls.add(MediaControl.stop);

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,

        systemActions: controls
            .toSet()
            .cast<MediaAction>(), // Crucial for Android notification buttons
        processingState:
            {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[processingState] ??
            AudioProcessingState.idle,
        playing: playing,
      ),
    );
  }

  Future<void> _playStation(RadioStation station) async {
    _currentStation = station;
    mediaItem.add(station.toMediaItem());

    await _player.stop();

    print("Attempting to play: ${station.name}");
    print("Stream URL: ${station.streamUrl}");

    const Map<String, String> richHeaders = {
      // Common User-Agent for better compatibility
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',

      // FIX FOR 403: Use the official website as the Referer
      // This is required by many media servers for geo-restricted or protected streams.
      'Referer': 'https://akashvani.gov.in/',

      // FIX FOR GZIP/PROTOCOL ERROR: Explicitly request no compression.
      // This bypasses the stream server's potential incorrect Content-Encoding header.
      'Accept-Encoding': 'identity',

      // Standard headers
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };

    try {
      // Try HLS first for m3u8 streams
      if (station.streamUrl.toLowerCase().contains('.m3u8')) {
        await _player.setAudioSource(
          HlsAudioSource(Uri.parse(station.streamUrl), headers: richHeaders),
        );
        _lastExtractedStreamUrl = station.streamUrl;
      } else {
        // For direct streams
        await _player.setAudioSource(
          ProgressiveAudioSource(
            Uri.parse(station.streamUrl),
            headers: richHeaders,
          ),
        );
        _lastExtractedStreamUrl = station.streamUrl;
      }
      print('_lastExtractedStreamUrl:$_lastExtractedStreamUrl');
      await _player.play();
      _updatePlaybackState();
      print("Successfully started playback");
    } catch (error) {
      print("Error playing station ${station.name}: $error");

      // Try fallback method
      await _tryFallbackUrls(station, error);
    }
  }
  // radioplayerhandler.dart

  // ... (Inside the RadioPlayerHandler class)

  Future<void> _tryFallbackUrls(
    RadioStation station,
    dynamic initialError,
  ) async {
    // ... (definitions for isRedirectLoop and headers remain the same)
    final isRedirectLoop = initialError.toString().contains(
      'Redirect loop detected',
    );
    const Map<String, String> richHeaders = {
      // Common User-Agent for better compatibility
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',

      // FIX FOR 403: Use the official website as the Referer
      // This is required by many media servers for geo-restricted or protected streams.
      'Referer': 'https://akashvani.gov.in/',

      // FIX FOR GZIP/PROTOCOL ERROR: Explicitly request no compression.
      // This bypasses the stream server's potential incorrect Content-Encoding header.
      'Accept-Encoding': 'identity',

      // Standard headers
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };
    // Parse the original stream URL to use as the base for resolving relative paths
    final baseUri = Uri.parse(station.streamUrl);

    if (!isRedirectLoop) {
      try {
        // Try to extract direct stream URL from M3U8
        // 🚨 CRITICAL FIX: Add headers here to avoid 403 Forbidden on the http client request
        final response = await http.get(baseUri, headers: richHeaders);

        if (response.statusCode == 200) {
          final lines = response.body.split('\n');
          for (final line in lines) {
            if (line.trim().isNotEmpty && !line.startsWith('#')) {
              String relativeUrl = line.trim();

              final streamUri = baseUri.resolve(relativeUrl);
              String streamUrl = streamUri.toString();

              print("Trying extracted stream URL: $streamUrl");
              await _player.setUrl(
                streamUrl,
                headers: richHeaders, // Headers must be here for just_audio
              );
              // 💡 CRITICAL FIX: Save the actual stream URL!
              _lastExtractedStreamUrl = streamUrl;

              await _player.play();
              _updatePlaybackState();
              return;
            }
          }
        }
      } catch (e) {
        print("Error extracting from M3U8: $e");
      }
    } else {
      print("Skipping M3U8 extraction due to redirect loop.");
    }

    // Final fallback: Try common radio stream formats (.mp3)
    try {
      final fallbackUrl = station.streamUrl.replaceAll('.m3u8', '.mp3');
      print("Trying MP3 fallback: $fallbackUrl");
      await _player.setUrl(
        fallbackUrl,
        headers: richHeaders, // Headers must be here for just_audio
      );
      await _player.play();
      _updatePlaybackState();
    } catch (e) {
      print("MP3 fallback also failed: $e");
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  // Custom method to play a specific station
  Future<void> playStation(RadioStation station) async {
    await _playStation(station);
  }

  // Get current station
  RadioStation? get currentStation => _currentStation;

  // Check if loading
  bool get isLoading => _isLoading;

  // 💡 FIX: Public getter to expose the recording status to the UI
  bool get isRecording => _isRecording;
}
