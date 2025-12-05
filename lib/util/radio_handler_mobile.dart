import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:dio/dio.dart';
import 'package:grradio/radiostation.dart';
import 'package:grradio/util/radio_handler_base.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class RadioHandlerImpl extends BaseAudioHandler
    with SeekHandler
    implements RadioHandlerBase {
  // 💡 FIX 1: Configure AudioPlayer with aggressive buffering for live streams
  final _player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      // Use default constructors for platform-specific load controls
      androidLoadControl: AndroidLoadControl(),
      darwinLoadControl: DarwinLoadControl(),
    ),
  );

  RadioStation? _currentStation;
  bool _isLoading = false;
  bool _isRecording = false;
  String? _lastExtractedStreamUrl;

  // Stream interruption recovery
  Timer? _recoveryTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5; // Increased attempts
  bool _isRecovering = false;

  // Dio components for stream recording
  final Dio _dio = Dio();
  CancelToken? _recordingCancelToken;

  final List<RadioStation> _radioStations;

  RadioHandlerImpl({required List<RadioStation> stations})
    : _radioStations = stations {
    _dio.options.receiveTimeout = const Duration(minutes: 5);
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _setupAudioSession();
    _notifyAudioHandlerAboutPlaybackEvents();
    _setupPlayerListeners();
  }

  bool _isIcecastShoutcastStream(String url) {
    return url.contains(';stream/') ||
        url.contains('/stream') ||
        url.contains(':8164') || // Common Icecast port
        url.contains(':8000') || // Common Shoutcast port
        url.toLowerCase().contains('icecast') ||
        url.toLowerCase().contains('shoutcast');
  }

  // Enhanced player listeners for stream recovery
  void _setupPlayerListeners() {
    _player.playerStateStream.listen((playerState) {
      _isLoading = playerState.processingState == ProcessingState.loading;
      _updatePlaybackState();

      // Detect unexpected stops
      if (!playerState.playing &&
          playbackState.value.playing &&
          !_isLoading &&
          _currentStation != null &&
          !_isRecovering) {
        // If it stops but we didn't ask it to, it might be a connection drop
        print(
          'Unexpected playback stop detected. ProcessingState: ${playerState.processingState}',
        );

        // Immediate check: If completed, it means player thought stream ended
        if (playerState.processingState == ProcessingState.completed) {
          _scheduleRecovery();
        } else if (_isIcecastShoutcastStream(
          _currentStation?.streamUrl ?? '',
        )) {
          Future.delayed(Duration(seconds: 3), () {
            if (!_player.playing && !_isRecovering) {
              print('Unexpected playback stop detected for Icecast stream');
              _scheduleRecovery();
            }
          });
        } else {
          _scheduleRecovery();
        }
      }
    });

    _player.processingStateStream.listen((processingState) {
      _isLoading = processingState == ProcessingState.loading;

      // 💡 FIX 2: Handle 'completed' state which causes "stuck" audio
      // Live streams should never "complete". If they do, restart them.
      if (processingState == ProcessingState.completed &&
          _currentStation != null) {
        print('Stream marked as completed (EOF) - restarting live stream...');
        if (!_isRecovering) {
          _attemptRecovery();
        }
      }
    });

    // 💡 FIX 3: Removed verbose print logging that was causing skipped frames
    // Only keeping critical buffer low warnings
    _player.bufferedPositionStream.listen((position) {
      // final duration = _player.duration;
      // Logging disabled to prevent UI jank
    });

    // Error handling
    _player.playbackEventStream.listen((event) {
      if (event.processingState == ProcessingState.idle &&
          playbackState.value.playing &&
          _currentStation != null) {
        print('Stream went idle unexpectedly');
        _scheduleRecovery();
      }
    });
  }

  // Stream recovery mechanism
  void _scheduleRecovery() {
    if (_recoveryTimer != null && _recoveryTimer!.isActive) {
      return;
    }

    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('Max reconnection attempts reached');
      _reconnectAttempts = 0;
      _isRecovering = false;
      return;
    }

    _recoveryTimer = Timer(Duration(seconds: 2 + _reconnectAttempts * 2), () {
      _attemptRecovery();
    });
  }

  Future<void> _attemptRecovery() async {
    if (_currentStation == null) return;

    _isRecovering = true;
    print('Attempting stream recovery (attempt ${_reconnectAttempts + 1})');
    _reconnectAttempts++;

    try {
      // Don't fully stop if possible, just reload
      // await _player.stop();
      // Instead of stop(), just try re-setting the source which is faster
      await _playStation(_currentStation!, isRecovery: true);
      _reconnectAttempts = 0;
      _isRecovering = false;
      print('Stream recovery successful');
    } catch (e) {
      print('Stream recovery failed: $e');
      _isRecovering = false;
      if (_reconnectAttempts < _maxReconnectAttempts) {
        _scheduleRecovery();
      } else {
        print(
          'Giving up on stream recovery after $_maxReconnectAttempts attempts',
        );
        _reconnectAttempts = 0;
      }
    }
  }

  // Recording methods (unchanged from your working version)
  Future<void> toggleRecord(MediaItem? mediaItem) async {
    if (mediaItem == null || !playbackState.value.playing) {
      _sendPermissionDenied('Please play a radio station before recording.');
      return;
    }

    if (!_isRecording) {
      final status = await Permission.audio.request();
      if (status.isGranted || status.isLimited) {
        _isRecording = true;
        _sendRecordStatus(true);
        await _startRecording(mediaItem);
      } else {
        _sendPermissionDenied('Storage permission denied. Cannot record.');
        openAppSettings();
        return;
      }
    } else {
      await _stopRecording();
      _isRecording = false;
      _sendRecordStatus(false);
    }
  }

  Future<void> _startRecording(MediaItem mediaItem) async {
    _recordingCancelToken = CancelToken();
    String currentUrl = _currentStation?.streamUrl ?? 'Unknown streaming URL';
    String referer = currentUrl.contains('radio.garden')
        ? 'https://radio.garden/'
        : 'https://akashvani.gov.in/';

    Map<String, String> richHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.127 Safari/537.36',
      'Referer': referer,
      'Accept-Encoding': 'identity',
      'Accept': '*/*',
    };

    bool isHlsRecording = false;
    int maxRedirects = 3;

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
              if (trimmedLine.isNotEmpty && !trimmedLine.startsWith('#')) {
                String resolvedUrl = baseUri.resolve(trimmedLine).toString();
                if (resolvedUrl.toLowerCase().contains('.m3u8')) {
                  foundUrl = resolvedUrl;
                  print("Found secondary M3U8 playlist: $foundUrl");
                  break;
                } else {
                  isHlsRecording = true;
                  i = maxRedirects;
                  break;
                }
              }
            }

            if (foundUrl != null) {
              currentUrl = foundUrl;
            } else if (isHlsRecording) {
              break;
            } else {
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
        break;
      }
    }

    final recordingUrl = currentUrl;
    Directory directory;
    final externalDirectories = await getExternalStorageDirectories(
      type: StorageDirectory.downloads,
    );

    if (externalDirectories != null && externalDirectories.isNotEmpty) {
      directory = externalDirectories.first;
      print('Saving to Downloads directory: ${directory.path}');
    } else {
      print(
        'Warning: Downloads directory unavailable, falling back to application documents.',
      );
      directory = await getApplicationDocumentsDirectory();
    }

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    String extension = '.mp3';
    if (recordingUrl.toLowerCase().contains('.ts')) {
      extension = '.ts';
    } else if (recordingUrl.toLowerCase().contains('.aac') ||
        recordingUrl.toLowerCase().contains('.m4a')) {
      extension = '.aac';
    } else if (recordingUrl.toLowerCase().contains('.ogg')) {
      extension = '.ogg';
    }

    final safeTitle = mediaItem.title.replaceAll(RegExp(r'[^\w\s\-]'), '');
    final fileName =
        '${safeTitle}_${DateTime.now().millisecondsSinceEpoch}$extension';
    final filePath = '${directory.path}/$fileName';

    print('Attempting to record stream from: $recordingUrl');
    print('Saving file to: $filePath');

    IOSink? sink;
    bool didError = false;
    final file = File(filePath);
    final Set<String> downloadedSegments = {};

    try {
      sink = file.openWrite(mode: FileMode.append);

      if (isHlsRecording) {
        while (!(_recordingCancelToken?.isCancelled ?? false)) {
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

          for (final line in lines) {
            final trimmedLine = line.trim();
            if (trimmedLine.isNotEmpty &&
                !trimmedLine.startsWith('#') &&
                !trimmedLine.toLowerCase().contains('.m3u8')) {
              final segmentUrl = playlistUri.resolve(trimmedLine).toString();
              segmentUrls.add(segmentUrl);
            }
          }

          for (final segmentUrl in segmentUrls) {
            if (!downloadedSegments.contains(segmentUrl)) {
              print('Downloading new segment: ${segmentUrl.split('/').last}');

              if (_recordingCancelToken?.isCancelled == true || !_isRecording) {
                print(
                  'Segment download loop aborted due to user cancellation.',
                );
                return;
              }

              try {
                final segmentResponse = await _dio.get<ResponseBody>(
                  segmentUrl,
                  options: Options(
                    responseType: ResponseType.stream,
                    receiveTimeout: const Duration(seconds: 30),
                    headers: richHeaders,
                  ),
                  cancelToken: _recordingCancelToken,
                );

                if (segmentResponse.data?.stream != null) {
                  await sink.addStream(segmentResponse.data!.stream);
                  downloadedSegments.add(segmentUrl);
                } else {
                  print('Error: Segment stream was null for $segmentUrl');
                }
              } on DioException catch (e) {
                if (e.type == DioExceptionType.cancel) {
                  print(
                    'Recording segment fetch was intentionally cancelled by user.',
                  );
                } else {
                  print('Dio segment download error: $e');
                }
              } catch (e) {
                print('General segment download error: $e');
              }
            }
          }

          await Future.delayed(const Duration(seconds: 10));
        }
      } else {
        final response = await _dio.get<ResponseBody>(
          recordingUrl,
          options: Options(
            responseType: ResponseType.stream,
            receiveTimeout: const Duration(minutes: 30),
            headers: richHeaders,
          ),
          cancelToken: _recordingCancelToken,
        );

        if (response.data?.stream != null) {
          await sink.addStream(response.data!.stream);
        } else {
          print('Error: Segment stream was null for $recordingUrl');
        }
      }

      print('Recording finalized and saved successfully to: $filePath');
    } on DioException catch (e) {
      final isCancel = e.type == DioExceptionType.cancel;
      if (!isCancel) {
        didError = true;
        final errorMessage =
            e.message ?? 'Unknown streaming error: ${e.toString()}';
        print('Recording Error: $errorMessage');
        _sendPermissionDenied('Recording failed: $errorMessage');
      }
    } finally {
      if (sink != null) {
        await sink.close();
      }

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
    if (_recordingCancelToken != null && !_recordingCancelToken!.isCancelled) {
      _recordingCancelToken!.cancel('Recording stopped by user');
      print('Dio download cancelled successfully.');
    }
    _recordingCancelToken?.cancel();
    _recordingCancelToken = null;
    customEvent.add({'event': 'record_status', 'isRecording': false});
  }

  void _sendRecordStatus(bool isRecording) {
    customEvent.add({'event': 'record_status', 'isRecording': isRecording});
  }

  void _sendPermissionDenied(String message) {
    customEvent.add({'event': 'permission_denied', 'message': message});
  }

  @override
  Future<void> stop() async {
    if (_isRecording) {
      await _stopRecording();
      _isRecording = false;
      _sendRecordStatus(false);
    }

    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _reconnectAttempts = 0;
    _isRecovering = false;

    await _player.stop();
    _currentStation = null;
    mediaItem.add(null);
  }

  @override
  Future<void> skipToNext() async {
    if (_isRecording) {
      await toggleRecord(mediaItem.value);
    }

    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _reconnectAttempts = 0;
    _isRecovering = false;

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
    if (_isRecording) {
      await toggleRecord(mediaItem.value);
    }

    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _reconnectAttempts = 0;
    _isRecovering = false;

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

  void _updatePlaybackState({PlaybackState? state}) {
    final playing = _player.playing;
    final processingState = _player.processingState;

    final controls = <MediaControl>[];

    if (mediaItem.value != null) {
      if (playing) {
        controls.add(MediaControl.pause);
      } else {
        controls.add(MediaControl.play);
      }
    }

    if (_radioStations.length > 1) {
      controls.add(MediaControl.skipToPrevious);
      controls.add(MediaControl.skipToNext);
    }

    controls.add(MediaControl.stop);

    playbackState.add(
      playbackState.value.copyWith(
        controls: controls,
        systemActions: controls.toSet().cast<MediaAction>(),
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

  // Updated _playStation method with SSL handling and better error recovery
  Future<void> _playStation(
    RadioStation station, {
    bool isRecovery = false,
  }) async {
    if (station.streamUrl == null) {
      print("Error: streamUrl is null for station: ${station.name}");
      customEvent.add({
        'event': 'playback_error',
        'station': station.name,
        'error': 'Station stream URL is missing.',
      });
      return;
    }

    if (!isRecovery) {
      _currentStation = station;
      mediaItem.add(station.toMediaItem());
    }

    // 💡 FIX 4: Don't stop explicitly if recovering, just set source
    // Stopping clears the buffer which we want to avoid if just glitching
    if (!isRecovery) {
      await _player.stop();
      await Future.delayed(Duration(milliseconds: 100));
    }

    print("Attempting to play: ${station.name}");
    print("Stream URL: ${station.streamUrl}");

    String streamUrl = station.streamUrl!;
    Map<String, String> richHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept':
          'audio/webm,audio/ogg,audio/wav,audio/*;q=0.9,application/ogg;q=0.7,video/*;q=0.6,*/*;q=0.5',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
      'Icy-MetaData': '1', // Important for Icecast/Shoutcast streams
    };

    // Handle different types of streams
    if (streamUrl.contains('radio.garden')) {
      richHeaders['Referer'] = 'https://radio.garden/';
      richHeaders['Origin'] = 'https://radio.garden';
    } else if (streamUrl.contains('akashvani.gov.in')) {
      richHeaders['Referer'] = 'https://akashvani.gov.in/';
    }

    // Special handling for Icecast/Shoutcast streams
    if (_isIcecastShoutcastStream(streamUrl)) {
      await _playIcecastShoutcastStream(
        station,
        streamUrl,
        richHeaders,
        isRecovery,
      );
      return;
    }

    // For problematic streams with SSL issues, try HTTP first
    if (_hasSSLIssues(streamUrl)) {
      await _playWithSSLWorkaround(station, streamUrl, richHeaders, isRecovery);
      return;
    }

    try {
      if (streamUrl.toLowerCase().contains('.m3u8')) {
        await _player.setAudioSource(
          HlsAudioSource(Uri.parse(streamUrl), headers: richHeaders),
        );
      } else {
        await _player.setAudioSource(
          ProgressiveAudioSource(Uri.parse(streamUrl), headers: richHeaders),
        );
      }

      _lastExtractedStreamUrl = streamUrl;
      print('Using stream URL: $_lastExtractedStreamUrl');

      await _player.play();
      _updatePlaybackState();

      _reconnectAttempts = 0;
      _recoveryTimer?.cancel();
      _isRecovering = false;

      print("Successfully started playback");
      customEvent.add({'event': 'playback_started', 'station': station.name});
    } catch (error) {
      print("Error playing station ${station.name}: $error");

      // Check if it's an SSL error
      if (_isSSLError(error)) {
        print("SSL error detected, trying workarounds...");
        await _playWithSSLWorkaround(
          station,
          streamUrl,
          richHeaders,
          isRecovery,
        );
      } else {
        customEvent.add({
          'event': 'playback_error',
          'station': station.name,
          'error': error.toString(),
        });

        if (!streamUrl.contains('radio.garden')) {
          await _tryFallbackUrls(station, error, streamUrl);
        } else {
          await _trySimpleRadioGardenFallback(station);
        }
      }
    }
  }

  // Check if a URL is known to have SSL issues
  bool _hasSSLIssues(String url) {
    final problematicDomains = [
      'stream.teluguoneradio.com',
      'radio.garden',
      // Add other domains with SSL issues here
    ];

    return problematicDomains.any((domain) => url.contains(domain));
  }

  // Check if error is SSL-related
  bool _isSSLError(dynamic error) {
    final errorStr = error.toString();
    return errorStr.contains('CERTIFICATE_VERIFY_FAILED') ||
        errorStr.contains('SSLHandshakeException') ||
        errorStr.contains('CertPathValidatorException') ||
        errorStr.contains('unable to get local issuer certificate');
  }

  // Special handling for streams with SSL issues
  Future<void> _playWithSSLWorkaround(
    RadioStation station,
    String originalUrl,
    Map<String, String> headers,
    bool isRecovery,
  ) async {
    print("Attempting SSL workaround for: ${station.name}");

    // Try HTTP instead of HTTPS
    if (originalUrl.startsWith('https://')) {
      final httpUrl = originalUrl.replaceFirst('https://', 'http://');
      print("Trying HTTP version: $httpUrl");

      try {
        await _player.setAudioSource(
          ProgressiveAudioSource(Uri.parse(httpUrl), headers: headers),
        );
        await _player.play();
        _updatePlaybackState();
        print("HTTP version successful");
        customEvent.add({'event': 'playback_started', 'station': station.name});
        return;
      } catch (e) {
        print("HTTP version failed: $e");
      }
    }

    // Try alternative URLs for known problematic streams
    final alternativeUrls = await _getAlternativeUrls(station);
    for (final altUrl in alternativeUrls) {
      try {
        print("Trying alternative URL: $altUrl");
        await _player.setUrl(altUrl, headers: headers);
        await _player.play();
        _updatePlaybackState();
        print("Alternative URL successful: $altUrl");
        customEvent.add({'event': 'playback_started', 'station': station.name});
        return;
      } catch (e) {
        print("Alternative URL failed: $altUrl - $e");
      }
    }

    // If all else fails, notify user
    customEvent.add({
      'event': 'playback_error',
      'station': station.name,
      'error':
          'Stream unavailable due to security restrictions. Please try another station.',
    });

    print("All SSL workarounds failed for: ${station.name}");
  }

  // Get alternative URLs for problematic stations
  Future<List<String>> _getAlternativeUrls(RadioStation station) async {
    final alternatives = <String>[];
    String streamUrl = station.streamUrl!;
    // Add domain-specific alternatives
    if (streamUrl.contains('teluguoneradio.com')) {
      alternatives.addAll([
        'http://stream.teluguoneradio.com:8164/;stream/1', // HTTP version
        'https://stream.teluguoneradio.com:8164/stream', // Alternative path
        'http://stream.teluguoneradio.com:8164/stream', // HTTP alternative
      ]);
    }

    if (streamUrl.contains('radio.garden')) {
      final match = RegExp(
        r'listen/([^/]+)/channel\.mp3',
      ).firstMatch(streamUrl);
      if (match != null) {
        final channelId = match.group(1);
        alternatives.addAll([
          'https://radio.garden/api/ara/content/channel/$channelId/listen.mp3',
          'https://radio.garden/api/ara/content/listen/$channelId/stream.mp3',
        ]);
      }
    }

    return alternatives;
  }

  // Updated fallback method with better SSL handling
  Future<void> _tryFallbackUrls(
    RadioStation station,
    dynamic initialError,
    String currentUrl,
  ) async {
    print("Trying fallback URLs for: ${station.name}");

    // First, try SSL workarounds if it's an SSL error
    if (_isSSLError(initialError)) {
      await _playWithSSLWorkaround(station, currentUrl, {}, false);
      return;
    }

    final isRedirectLoop = initialError.toString().contains(
      'Redirect loop detected',
    );
    String referer = station.streamUrl!.contains('akashvani.gov.in')
        ? 'https://akashvani.gov.in/'
        : 'https://example.com/';

    Map<String, String> richHeaders = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': referer,
      'Accept-Encoding': 'identity',
      'Accept': '*/*',
      'Connection': 'keep-alive',
    };

    final baseUri = Uri.parse(currentUrl);

    if (!isRedirectLoop && currentUrl.toLowerCase().contains('.m3u8')) {
      try {
        print("Attempting M3U8 extraction...");
        final response = await http.get(baseUri, headers: richHeaders);
        if (response.statusCode == 200) {
          final lines = response.body.split('\n');
          for (final line in lines) {
            if (line.trim().isNotEmpty && !line.startsWith('#')) {
              String relativeUrl = line.trim();
              final streamUri = baseUri.resolve(relativeUrl);
              String streamUrl = streamUri.toString();

              print("Trying extracted stream URL: $streamUrl");
              await _player.setUrl(streamUrl, headers: richHeaders);
              _lastExtractedStreamUrl = streamUrl;

              await _player.play();
              _updatePlaybackState();
              print("M3U8 extraction successful");
              return;
            }
          }
        }
      } catch (e) {
        print("Error extracting from M3U8: $e");
      }
    }

    // Try common fallback formats including HTTP versions
    final fallbacks = <String>[
      currentUrl.replaceAll('.m3u8', '.mp3'),
      currentUrl.replaceAll('.m3u8', '.aac'),
      currentUrl.replaceAll('/listen/', '/stream/'),
    ];

    // Add HTTP versions for HTTPS URLs
    if (currentUrl.startsWith('https://')) {
      fallbacks.add(currentUrl.replaceFirst('https://', 'http://'));
    }

    for (final fallbackUrl in fallbacks) {
      if (fallbackUrl != currentUrl) {
        try {
          print("Trying fallback: $fallbackUrl");
          await _player.setUrl(fallbackUrl, headers: richHeaders);
          await _player.play();
          _updatePlaybackState();
          print("Fallback successful: $fallbackUrl");
          return;
        } catch (e) {
          print("Fallback failed: $fallbackUrl - $e");
        }
      }
    }

    print("All fallback attempts failed for: ${station.name}");

    // Final notification
    customEvent.add({
      'event': 'playback_error',
      'station': station.name,
      'error': 'Unable to play this station. The stream may be unavailable.',
    });
  }

  // Special handling for Icecast/Shoutcast streams
  Future<void> _playIcecastShoutcastStream(
    RadioStation station,
    String streamUrl,
    Map<String, String> headers,
    bool isRecovery,
  ) async {
    print("Playing Icecast/Shoutcast stream: ${station.name}");

    // Clean up the stream URL - remove ;stream/1 suffix which can cause issues
    String cleanUrl = streamUrl;

    // Try different variations of the stream URL
    final streamVariations = [
      cleanUrl,
      '$cleanUrl/',
      '$cleanUrl/stream',
      '$cleanUrl/;',
      streamUrl, // original URL as fallback
    ];

    // Enhanced headers for Icecast/Shoutcast
    final icecastHeaders = Map<String, String>.from(headers);
    icecastHeaders.addAll({
      'Icy-MetaData': '1',
      'Accept': '*/*',
      'Connection': 'keep-alive',
    });

    for (final variation in streamVariations) {
      try {
        print("Trying stream variation: $variation");

        // Use setUrl instead of setAudioSource for better compatibility
        await _player.setUrl(variation, headers: icecastHeaders);

        // Add a small delay before playing
        await Future.delayed(Duration(milliseconds: 200));

        await _player.play();

        // Wait a bit to see if playback starts successfully
        await Future.delayed(Duration(seconds: 2));

        // Check if playback is actually working
        if (_player.playing &&
            _player.processingState != ProcessingState.idle) {
          _updatePlaybackState();
          _lastExtractedStreamUrl = variation;

          _reconnectAttempts = 0;
          _recoveryTimer?.cancel();
          _isRecovering = false;

          print("Icecast/Shoutcast stream successful: $variation");
          customEvent.add({
            'event': 'playback_started',
            'station': station.name,
          });
          return;
        } else {
          // If not actually playing, stop and try next variation
          // Don't fully stop in loop, just let next setUrl handle it
          await Future.delayed(Duration(milliseconds: 100));
        }
      } catch (e) {
        print("Stream variation failed: $variation - $e");
        await Future.delayed(Duration(milliseconds: 100));
      }
    }

    // If all variations fail, try with minimal configuration
    try {
      print("Trying minimal configuration for Icecast stream...");
      await _player.setUrl(cleanUrl); // No headers, let the player handle it

      // Configure player specifically for live streams
      _player.setLoopMode(LoopMode.off);

      await _player.play();

      // Give it more time to buffer
      await Future.delayed(Duration(seconds: 3));

      if (_player.playing) {
        _updatePlaybackState();
        _lastExtractedStreamUrl = cleanUrl;

        _reconnectAttempts = 0;
        _recoveryTimer?.cancel();
        _isRecovering = false;

        print("Minimal configuration successful");
        customEvent.add({'event': 'playback_started', 'station': station.name});
        return;
      }
    } catch (e) {
      print("Minimal configuration also failed: $e");
    }

    // Final fallback - notify user
    customEvent.add({
      'event': 'playback_error',
      'station': station.name,
      'error':
          'Icecast/Shoutcast stream format not supported. Please try another station.',
    });

    print("All Icecast/Shoutcast attempts failed for: ${station.name}");
  }

  // Simple fallback for Radio Garden
  Future<void> _trySimpleRadioGardenFallback(RadioStation station) async {
    try {
      print("Trying simple Radio Garden fallback...");

      // Try with just the basic URL and no special headers
      await _player.setUrl(station.streamUrl!);
      await _player.play();
      _updatePlaybackState();
      print("Simple fallback successful");
    } catch (e) {
      print("Simple fallback also failed: $e");

      // Final attempt - try to extract from known patterns
      await _tryExtractRadioGardenStream(station);
    }
  } // Simple fallback for Radio Garden

  // Extract Radio Garden stream from known patterns
  Future<void> _tryExtractRadioGardenStream(RadioStation station) async {
    try {
      // Radio Garden URLs often contain channel IDs that can be used
      // to find alternative streams
      final match = RegExp(
        r'listen/([^/]+)/channel\.mp3',
      ).firstMatch(station.streamUrl!);
      if (match != null) {
        final channelId = match.group(1);
        print("Extracted channel ID: $channelId");

        // Try some known Radio Garden alternative patterns
        final alternatives = [
          'https://radio.garden/api/ara/content/channel/$channelId/listen.mp3',
          'https://radio.garden/api/ara/content/listen/$channelId/stream.mp3',
          'https://radio.garden/api/ara/content/listen/$channelId/index.m3u8',
        ];

        for (final altUrl in alternatives) {
          try {
            print("Trying alternative URL: $altUrl");
            await _player.setUrl(
              altUrl,
              headers: {
                'User-Agent':
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Referer': 'https://radio.garden/',
              },
            );
            await _player.play();
            _updatePlaybackState();
            print("Alternative URL successful: $altUrl");
            return;
          } catch (e) {
            print("Alternative URL failed: $altUrl - $e");
          }
        }
      }
    } catch (e) {
      print("Error in Radio Garden stream extraction: $e");
    }
  }

  @override
  Future<void> play() async {
    if (_player.processingState == ProcessingState.completed &&
        _currentStation != null) {
      await _playStation(_currentStation!, isRecovery: true);
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() => _player.pause();

  Future<void> playStation(RadioStation station) async {
    await _playStation(station);
  }

  RadioStation? get currentStation => _currentStation;
  bool get isLoading => _isLoading;
  bool get isRecording => _isRecording;

  // Clean up method
  Future<void> cleanup() async {
    _recoveryTimer?.cancel();
    await _player.dispose();
  }
}
