// lib/mp3playerhandler.dart

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:grradio/ads/ad_helper.dart'; // Assuming AdHelper is here
import 'package:just_audio/just_audio.dart';

// Define the type for the songs coming from your search results
typedef SongData = Map<String, dynamic>;

class Mp3PlayerHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  StreamSubscription? _playerStateSubscription;

  // The flag to control ad interruption
  bool _adSequenceActive = false;

  Mp3PlayerHandler() {
    _init();
  }

  void _init() async {
    // 1. Set the playlist and player states
    await _player.setAudioSource(_playlist);

    // 2. Listen for the end of a song
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          _player.currentIndex != null) {
        // A song has finished, trigger the ad sequence.
        _adSequenceActive = true;
        _player.stop(); // 🛑 Stop playback immediately after completion

        // Show Interstitial Ad
        AdHelper.showInterstitialAd(
          onAdClosed: () {
            // After ad closes, play the next song
            _adSequenceActive = false;
            _playNextTrack();
          },
        );
      }
      _updatePlaybackState();
    });

    // 3. Notify the system about changes in the queue
    _player.sequenceStateStream.listen((sequenceState) {
      final sequence = sequenceState?.effectiveSequence;
      if (sequence == null) return;

      // Update the queue list for the system media controls
      queue.add(sequence.map((source) => source.tag as MediaItem).toList());

      // Update the current media item
      mediaItem.add(sequenceState!.currentSource?.tag as MediaItem?);
    });
  }

  // Converts your search results map to an AudioSource
  AudioSource _createAudioSource(SongData song) {
    return AudioSource.uri(
      Uri.parse(song['url'] as String),
      tag: MediaItem(
        id: song['url'] as String,
        album: song['album'] as String? ?? 'MP3 Downloads',
        title: song['name'] as String? ?? 'Unknown Song',
        artist: song['artist'] as String? ?? 'Unknown Artist',
        duration: Duration.zero, // You might need to estimate/fetch this
      ),
    );
  }

  // Public method to start the entire queue
  Future<void> startQueue(List<SongData> songs, int startIndex) async {
    // 1. Stop any current playback
    await _player.stop();

    // 2. Prepare the new playlist
    final sources = songs.map(_createAudioSource).toList();
    await _playlist.clear();
    await _playlist.addAll(sources);

    // 3. Jump to the starting song and play
    await _player.seek(Duration.zero, index: startIndex);
    play();
  }

  // Internal method to handle playing the next song
  void _playNextTrack() {
    if (_player.hasNext) {
      skipToNext();
      play();
    }
  }

  // --- AudioHandler Overrides ---
  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    // Cancel the listener subscription
    _playerStateSubscription?.cancel(); // Cancel the stream

    // Dispose the audio player resources
    await _player.dispose(); // Dispose of the just_audio player

    // Call the superclass stop method
    return super.stop(); // 💡 CORRECT: Use the stop method for final cleanup
  }

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      // If no next song, stop the player
      await stop();
    }
  }

  // Other overrides (skipToPrevious, seek, etc.) should also be implemented.

  void _updatePlaybackState() {
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          // Define controls (play, pause, next, previous)
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: _player.playing,
        updatePosition: _player.position,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _player.dispose();
    super.stop();
  }
}
