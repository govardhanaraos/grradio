// lib/mp3playerhandler.dart

import 'dart:async';

// Note: Removed 'package:audio_service/audio_service.dart' as this is now a regular service
import 'package:grradio/ads/ad_helper.dart'; // Assuming AdHelper is here
import 'package:just_audio/just_audio.dart';

// Define the type for the songs coming from your search results
typedef SongData = Map<String, dynamic>;

class Mp3PlayerHandler {
  final AudioPlayer _player = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  StreamSubscription? _playerStateSubscription;

  // The flag to control ad interruption
  bool _adSequenceActive = false;

  Mp3PlayerHandler() {
    // 💡 Constructor is now empty. Public init() will be called from main.dart.
  }

  // 💡 FIX: Public init() method as required by main.dart
  Future<void> init() async {
    // 1. Set the playlist and player states
    await _player.setAudioSource(_playlist);

    // 2. Listen for the end of a song
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          _player.currentIndex != null) {
        // A song has finished, trigger the ad sequence.
        _adSequenceActive = true;
        this.stop(); // 🛑 Stop playback immediately after completion

        // Show Interstitial Ad
        AdHelper.showInterstitialAd(
          onAdClosed: () {
            // After ad closes, play the next song
            _adSequenceActive = false;
            _playNextTrack();
          },
        );
      }
      // Note: System notification logic (like _updatePlaybackState) is removed
      // as this class no longer extends BaseAudioHandler.
    });
  }

  // Converts your search results map to an AudioSource
  AudioSource _createAudioSource(SongData song) {
    final String songUrl =
        song['url'] as String; // This assumes 'url' is never null.
    // If 'url' CAN be null, you must check it
    // BEFORE this function is called, as a player
    // cannot play a null URL.

    // It is highly likely the crash is happening on the 'url' field.
    // If the API allows a null 'url', you must filter those songs out
    // in mp3downloadresults.dart *before* calling startQueue.

    // However, let's fix the other two tags, which are common sources of this error:
    final String songTitle = song['name'] as String? ?? 'Unknown Song';
    final String songArtist = song['artist'] as String? ?? 'Unknown Artist';
    return AudioSource.uri(
      Uri.parse(songUrl),
      tag: {'id': songUrl, 'title': songTitle, 'artist': songArtist},
    );
  }

  // Public method to start the entire queue
  Future<void> startQueue(List<SongData> songs, int startIndex) async {
    // 1. Stop any current playback
    await this.stop();

    // 2. Prepare the new playlist
    final sources = songs.map(_createAudioSource).toList();
    await _playlist.clear();
    await _playlist.addAll(sources);

    // 3. Jump to the starting song and play
    await _player.seek(Duration.zero, index: startIndex);
    this.play();
  }

  // Internal method to handle playing the next song
  void _playNextTrack() {
    if (_player.hasNext) {
      this.skipToNext();
      this.play();
    }
  }

  // --- Public Player Control Methods (Former AudioHandler Overrides) ---

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  // 💡 FIX: Updated stop method (Cleaned up BaseAudioHandler dependency)
  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero); // Reset position
  }

  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      // If no next song, stop the player
      await stop();
    }
  }

  // Optional: Add a dispose method for app-wide cleanup
  void dispose() {
    _playerStateSubscription?.cancel();
    _player.dispose();
  }

  // Note: Removed 'skipToPrevious', 'seek', and '_updatePlaybackState'
  // as they were tied to BaseAudioHandler which this class no longer extends.
}
