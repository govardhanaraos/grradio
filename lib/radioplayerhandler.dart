import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart'; // For kIsWeb
import 'package:grradio/radiostation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart'; // For file path access
import 'package:permission_handler/permission_handler.dart'; // For permission checks

class RadioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();
  RadioStation? _currentStation;
  bool _isLoading = false;
  // 💡 NEW: State to track recording status
  bool _isRecording = false;

  // 💡 FIX 1: New field to store the station list passed in the constructor
  final List<RadioStation> _radioStations;

  RadioPlayerHandler({required List<RadioStation> stations})
    : _radioStations = stations {
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
      // Cannot start recording if nothing is playing
      print("Cannot toggle recording: No media item or not playing.");
      return;
    }

    if (!_isRecording) {
      // --- Start Recording Simulation ---
      final filename = '${mediaItem.title.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.mp3';
      
      String savePath = "Downloads/$filename"; // Default display path

      if (!kIsWeb) {
        // 🚨 FIX: Use getApplicationDocumentsDirectory() instead of getExternalStoragePublicDirectory()
        // getExternalStoragePublicDirectory() is not part of path_provider package's public API.
        final directory = await getApplicationDocumentsDirectory();
        savePath = '${directory.path}/$filename';
      }

      print('SIMULATED: Started recording ${mediaItem.title}. Target path: $savePath');

      _isRecording = true;
      // You would start the actual stream capture here
      
      // 2. Send custom event to update the UI state
      _sendRecordStatus(true);
      
    } else {
      // --- Stop Recording Simulation ---
      print("SIMULATED: Recording stopped. File saved to Downloads.");
      
      // You would stop the actual stream capture here and finalize the file write
      _isRecording = false;

      // 3. Send custom event to update the UI state
      _sendRecordStatus(false);
    }
  }

  // Helper to send the custom event to the UI
  void _sendRecordStatus(bool isRecording) {
    customEvent.add({'event': 'record_status', 'isRecording': isRecording});
  }

  // Override to ensure recording stops when playback stops
  @override
  Future<void> stop() async {
    // 💡 NEW: Stop recording if playing stops
    if (_isRecording) {
      await toggleRecord(mediaItem.value);
    }

    await _player.stop();
    _currentStation = null;
    mediaItem.add(null);
  }

  // --- Other existing methods (setupAudioSession, notifyAudioHandler, updatePlaybackState, tryFallbackUrls, play, pause, skipToNext, skipToPrevious, playStation, currentStation, isLoading) remain the same ---
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
      } else {
        // For direct streams
        await _player.setAudioSource(
          ProgressiveAudioSource(
            Uri.parse(station.streamUrl),
            headers: richHeaders,
          ),
        );
      }

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

  @override
  Future<void> skipToNext() async {
    // 💡 NEW: Stop recording before changing station
    if (_isRecording) {
      await toggleRecord(mediaItem.value);
    }

    final currentIndex = _currentStation != null
        ? _radioStations.indexWhere(
            (station) => station.id == _currentStation!.id,
          )
        : -1;

    if (currentIndex != -1) {
      final nextIndex = (currentIndex + 1) % _radioStations.length;
      await _playStation(_radioStations[nextIndex]);
    } else if (_radioStations.isNotEmpty) {
      // If no station is playing, start with the first one
      await _playStation(_radioStations.first);
    }
  }

  @override
  Future<void> skipToPrevious() async {
    // 💡 NEW: Stop recording before changing station
    if (_isRecording) {
      await toggleRecord(mediaItem.value);
    }
    
    final currentIndex = _currentStation != null
        ? _radioStations.indexWhere(
            (station) => station.id == _currentStation!.id,
          )
        : -1;

    if (currentIndex != -1) {
      final prevIndex =
          (currentIndex - 1 + _radioStations.length) % _radioStations.length;
      await _playStation(_radioStations[prevIndex]);
    } else if (_radioStations.isNotEmpty) {
      // If no station is playing, start with the last one
      await _playStation(_radioStations.last);
    }
  }

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
