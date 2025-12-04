// lib/mp3playerhandler.dart

import 'dart:async';

import 'package:audio_service/audio_service.dart'
    as audio_service; // Alias for clarity
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart' as just_audio; // Alias for clarity
import 'package:rxdart/rxdart.dart'; // Required for Rx.combineLatest4

// Define the type for the songs coming from your search results
typedef SongData = Map<String, dynamic>;

class Mp3PlayerHandler extends audio_service.BaseAudioHandler
    with audio_service.QueueHandler, audio_service.SeekHandler {
  final just_audio.AudioPlayer _player = just_audio.AudioPlayer();
  final _playlist = just_audio.ConcatenatingAudioSource(children: []);
  StreamSubscription? _playerStateSubscription;

  // Stored for dynamic URL lookup logic
  String? _currentMp3TargetUrl;

  Mp3PlayerHandler() {
    _player.setAudioSource(_playlist);
    _setupListeners();

    // A. Sync queue
    // This pipe manages the queue. Do not call queue.add() manually!
    _player.sequenceStateStream
        .map((state) => state?.effectiveSequence)
        .distinct()
        .map(
          (sequence) =>
              sequence
                  ?.map((source) => source.tag as audio_service.MediaItem)
                  .toList() ??
              <audio_service.MediaItem>[],
        )
        .pipe(queue);

    // B. Sync PlaybackState
    Rx.combineLatest4<
          Duration,
          Duration,
          Duration?,
          just_audio.PlayerState,
          audio_service.PlaybackState
        >(
          _player.positionStream,
          _player.bufferedPositionStream,
          _player.durationStream,
          _player.playerStateStream,
          (position, bufferedPosition, duration, playerState) {
            final controls = [
              audio_service.MediaControl.skipToPrevious,
              if (playerState.playing)
                audio_service.MediaControl.pause
              else
                audio_service.MediaControl.play,
              audio_service.MediaControl.skipToNext,
              audio_service.MediaControl.stop,
            ];
            return audio_service.PlaybackState(
              controls: controls,
              systemActions: const {
                audio_service.MediaAction.seek,
                audio_service.MediaAction.seekForward,
                audio_service.MediaAction.seekBackward,
              },
              androidCompactActionIndices: const [0, 1, 2],
              processingState: _playerStateToProcessingState(
                playerState.processingState,
              ),
              playing: playerState.playing,
              updatePosition: position,
              bufferedPosition: bufferedPosition,
              speed: _player.speed,
            );
          },
        )
        .pipe(playbackState);
  }

  // 💡 Added init method to prevent main.dart errors if you re-add the call
  Future<void> init() async {
    // Perform any specific async initialization here if needed.
    // Currently, constructor handles most setup.
  }

  Future<void> setQueue(
    List<audio_service.MediaItem> items,
    String targetUrl,
  ) async {
    _currentMp3TargetUrl = targetUrl;

    // Create the new list of sources
    final sources = items.map((item) {
      return just_audio.AudioSource.uri(
        Uri.parse('asset:///dummy.mp3'),
        tag: item,
      );
    }).toList();

    try {
      // Try to modify the existing playlist
      await _playlist.clear();
      await _playlist.addAll(sources);
    } catch (e) {
      print("Error modifying playlist directly, resetting audio source: $e");
      // Fallback: If modification crashes, re-initialize the audio source completely
      // This avoids the native crash by resetting the underlying player state
      await _player.setAudioSource(
        _playlist,
        initialIndex: 0,
        initialPosition: Duration.zero,
      );
      // After resetting, we might need to add them again if the previous add failed
      if (_playlist.length == 0) {
        await _playlist.addAll(sources);
      }
    }

    // Manually update the current media item
    if (items.isNotEmpty) {
      mediaItem.add(items[0]);
    }
  }

  Future<void> loadAndPlayFirstSong() async {
    if (_playlist.length > 0) {
      final firstSource = _playlist.children.first as just_audio.UriAudioSource;
      final item = firstSource.tag as audio_service.MediaItem;
      await _loadAndPlaySong(item);
      // Ensure we are at the start
      await _player.seek(Duration.zero, index: 0);
      await _player.play();
    }
  }

  Future<void> _loadAndPlaySong(audio_service.MediaItem item) async {
    final fileId = item.id;
    final streamUrl = await _extractStreamUrl(fileId);

    final currentIndex = _player.currentIndex;

    // 1. SAFETY CHECK: Check index validity and ensure the item at the index
    // is still the one we intend to replace.
    if (currentIndex == null || currentIndex >= _playlist.length) {
      print('WARNING: Cannot load song. Invalid current index: $currentIndex');
      return;
    }

    final currentSource =
        _playlist.children[currentIndex] as just_audio.UriAudioSource;
    // Check if the source at this index is STILL the dummy one
    if (!currentSource.uri.toString().contains('dummy.mp3')) {
      print(
        'INFO: Source at index $currentIndex already replaced. Aborting load.',
      );
      return;
    }

    final wasPlaying = _player.playing;

    if (streamUrl == null) {
      print('ERROR: Could not load stream URL for song: ${item.title}');
      await skipToNext();
      return;
    }

    final newSource = just_audio.AudioSource.uri(
      Uri.parse(streamUrl),
      tag: item,
    );

    try {
      // 2. Remove the old (dummy) source
      await _playlist.removeAt(currentIndex);

      // 3. Insert the new (real URL) source at the same index
      await _playlist.insert(currentIndex, newSource);

      // 4. Force the player to load the new source by seeking to it
      // Do NOT use Duration.zero here, as the user might have paused/resumed midway
      // If we use seek(player.position) the player should load the new URI at the right time.
      await _player.seek(_player.position, index: currentIndex);

      // 5. Ensure playback resumes
      if (wasPlaying && !_player.playing) {
        await _player.play();
      }

      print('INFO: Successfully loaded and set stream for: ${item.title}');
    } catch (e) {
      print('CRITICAL ERROR during source replacement/seek: $e');
      // Final fallback: If modification fails, jump to next track
      await skipToNext();
    }

    // Update mediaItem for the UI
    mediaItem.add(item);
  }

  Future<void> updateQueue(List<audio_service.MediaItem> items) async {
    await setQueue(items, _currentMp3TargetUrl ?? '');
  }

  Future<void> startQueue(List<SongData> songs, int startIndex) async {
    // 1. Stop any current playback
    await stop();

    // 2. Prepare the new playlist
    final sources = songs.map(_createAudioSource).toList();
    await _playlist.clear();
    await _playlist.addAll(sources);

    // 3. Jump to the starting song and play
    await _player.seek(Duration.zero, index: startIndex);
    // The skip logic will call _loadAndPlaySong internally on playback start
    play();
  }

  just_audio.AudioSource _createAudioSource(SongData song) {
    // Note: Assuming SongData is Map<String, dynamic> here.
    final String songUrl = song['url'] as String;
    final String songTitle = song['name'] as String? ?? 'Unknown Song';
    final String songArtist = song['artist'] as String? ?? 'Unknown Artist';

    // Construct a MediaItem from the SongData to use as the tag.
    final audio_service.MediaItem mediaItemTag = audio_service.MediaItem(
      id: songUrl,
      title: songTitle,
      artist: songArtist,
      extras: song, // Optional: store the full original map here
    );

    return just_audio.AudioSource.uri(Uri.parse(songUrl), tag: mediaItemTag);
  }

  // 💡 FIXED: Adds to _playlist, does not touch queue manually
  Future<void> addQueueItem(audio_service.MediaItem item) async {
    final source = just_audio.AudioSource.uri(
      Uri.parse('asset:///dummy.mp3'),
      tag: item,
    );
    await _playlist.add(source);
    // 🛑 REMOVED: queue.add(...)
  }

  // 💡 FIX: Helper function to map Just Audio's state to Audio Service's state
  audio_service.AudioProcessingState _playerStateToProcessingState(
    just_audio.ProcessingState state,
  ) {
    switch (state) {
      case just_audio.ProcessingState.idle:
        return audio_service.AudioProcessingState.idle;
      case just_audio.ProcessingState.loading:
        return audio_service.AudioProcessingState.loading;
      case just_audio.ProcessingState.buffering:
        return audio_service.AudioProcessingState.buffering;
      case just_audio.ProcessingState.ready:
        return audio_service.AudioProcessingState.ready;
      case just_audio.ProcessingState.completed:
        return audio_service.AudioProcessingState.completed;
    }
  }

  void _setupListeners() {
    // 1. Handle Playback completion and update state (Existing Logic)
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      // Keep mediaItem in sync with current player index (You may have this already)
      if (_player.currentIndex != null &&
          _playlist.length > _player.currentIndex!) {
        final source =
            _playlist.children[_player.currentIndex!]
                as just_audio.UriAudioSource;
        mediaItem.add(source.tag as audio_service.MediaItem);
      }

      // We don't need to manually check for completion here, as the index stream handles the advance.
    });

    bool _isReplacingSource = false;

    // 💡 NEW CRITICAL LOGIC: Intercept track changes to load the real URL
    _player.currentIndexStream.listen((index) async {
      if (index == null || _playlist.children.isEmpty || _isReplacingSource)
        return;

      // Ensure the current song object is accessible
      if (index >= _playlist.children.length) return;

      final source = _playlist.children[index] as just_audio.UriAudioSource;
      final currentMediaItem = source.tag as audio_service.MediaItem;

      // Check if the current source is the dummy source
      if (source.uri.toString().contains('mp3')) {
        _isReplacingSource = true; // Block subsequent calls
        print(
          'INFO: Current index changed to $index. Loading real URL for: ${currentMediaItem.title}',
        );

        try {
          // This is the function that does the network fetch and source replacement
          await _loadAndPlaySong(currentMediaItem);
        } finally {
          _isReplacingSource = false; // Release the lock
        }
      }
    });
  }

  void _handlePlaybackCompletion() async {
    if (_player.hasNext) {
      await skipToNext();
    } else {
      await stop();
    }
  }

  Future<String?> _extractStreamUrl(String fileId) async {
    if (_currentMp3TargetUrl == null) return null;

    final url = '$_currentMp3TargetUrl/?fid=$fileId';
    print('Fetching stream URL from: $url');

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);

        // 1. Target the specific download options container, matching _fetchFileDetails logic
        final downloadOptionsDiv = document.querySelector('.download-options');

        if (downloadOptionsDiv != null) {
          final anchors = downloadOptionsDiv.querySelectorAll('a');

          String? bestUrl; // For 320kbps
          String? mediumUrl; // For 128kbps
          String? anyUrl; // Fallback

          for (final anchor in anchors) {
            final href = anchor.attributes['href'] ?? '';
            final text = anchor.text?.trim() ?? '';

            if (href.isNotEmpty) {
              // 2. Construct the full URL (Handling relative paths)
              String fullUrl;
              if (href.startsWith('http')) {
                fullUrl = href;
              } else {
                // Logic from _fetchFileDetails: '${widget.targetUrl}/$href'
                fullUrl = '$_currentMp3TargetUrl/$href';
              }

              // 3. Capture the first valid link as a fallback
              anyUrl ??= fullUrl;

              // 4. Prioritize Quality based on text content
              if (text.contains('320') || text.contains('High')) {
                bestUrl = fullUrl;
              } else if (text.contains('128') || text.contains('Medium')) {
                mediumUrl = fullUrl;
              }
            }
          }

          // 5. Return the best available URL
          final finalUrl = bestUrl ?? mediumUrl ?? anyUrl;
          print('finalURL : $finalUrl');
          if (finalUrl != null) {
            print('✅ Selected Stream URL: $finalUrl');
            return finalUrl;
          }
        }
      }
    } catch (e) {
      print('Error extracting stream URL for $fileId: $e');
    }
    return null;
  }

  // In Mp3PlayerHandler
  Future<void> playSingleSong(
    String fileId,
    String title,
    String targetUrl,
  ) async {
    _currentMp3TargetUrl = targetUrl;

    await _player.stop();

    final streamUrl = await _extractStreamUrl(fileId);
    print('fileId: $fileId');
    print('streamUrl: $streamUrl');
    if (streamUrl == null) {
      print('❌ Could not fetch stream URL for $title');
      return;
    }

    final mediaItemTag = audio_service.MediaItem(id: fileId, title: title);

    final source = just_audio.AudioSource.uri(
      Uri.parse(streamUrl),
      tag: mediaItemTag,
    );

    try {
      await _player.setAudioSource(source);
      await _player.play();

      // Stop automatically when finished
      _player.processingStateStream.listen((state) async {
        if (state == just_audio.ProcessingState.completed) {
          await stop(); // stop() already resets and clears
        }
      });

      mediaItem.add(mediaItemTag);
    } catch (e) {
      print('Error playing single song: $e');
    }
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? arguments,
  ]) async {
    // 💡 FIXED: Logic updated to avoid manual queue.add
    if (name == 'playQueueAndFirstSong' && arguments != null) {
      final List<audio_service.MediaItem> fullQueue =
          arguments['queue'] as List<audio_service.MediaItem>;
      final String initialUrl = arguments['initialUrl'] as String;
      final String targetUrl = arguments['targetUrl'] as String;

      _currentMp3TargetUrl = targetUrl;

      final sources = fullQueue.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;

        // Determine the correct URI for the AudioSource
        final Uri sourceUri = (index == 0)
            ? Uri.parse(
                initialUrl,
              ) // Use the actual, pre-fetched URL for the first song
            : Uri.parse('asset:///dummy.mp3'); // Use a dummy URI for the rest

        // Create the AudioSource with the MediaItem as the tag.
        return just_audio.AudioSource.uri(
          sourceUri,
          tag: item, // Pass the original MediaItem as the tag
        );
      }).toList();

      // Set the entire playlist
      await _playlist.clear();
      await _playlist.addAll(sources);

      // Start playback from the first song
      await _player.seek(Duration.zero, index: 0);
      await _player.play();

      // Update the audio service queue and current mediaItem
      queue.add(fullQueue);
      mediaItem.add(fullQueue.first);
      return;
    }
    return super.customAction(name, arguments);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  // 💡 NEW: Handle skipToNext by triggering the load logic for the new track
  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
      // Load the real URL for the next song
      final nextIndex = _player.currentIndex!;
      final source = _playlist.children[nextIndex] as just_audio.UriAudioSource;
      await _loadAndPlaySong(source.tag as audio_service.MediaItem);
    } else {
      await stop();
    }
  }

  // 💡 NEW: Handle skipToPrevious
  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
      final prevIndex = _player.currentIndex!;
      final source = _playlist.children[prevIndex] as just_audio.UriAudioSource;
      await _loadAndPlaySong(source.tag as audio_service.MediaItem);
    }
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    await _player.seek(Duration.zero); // Reset position
    mediaItem.add(null);
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    await _playerStateSubscription?.cancel();
    _player.dispose();
    return super.onTaskRemoved();
  }

  just_audio.AudioPlayer get player => _player;
}
