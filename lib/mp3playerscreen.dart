import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';


// 💡 NEW: MP3 Player Screen Implementation
class Mp3PlayerScreen extends StatefulWidget {
  @override
  _Mp3PlayerScreenState createState() => _Mp3PlayerScreenState();
}

class _Mp3PlayerScreenState extends State<Mp3PlayerScreen> {
  // Instance of the package to query audio files
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _mp3Player = AudioPlayer();

  bool _hasPermission = false;
  SongModel? _currentSong;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  @override
  void dispose() {
    _mp3Player.dispose();
    super.dispose();
  }

  void _checkAndRequestPermissions() async {
    // Check if we have permission to read storage
    if (await Permission.storage.request().isGranted || await Permission.mediaLibrary.request().isGranted) {
      setState(() {
        _hasPermission = true;
      });
    }
  }

  // Playback function for local files
  void _playSong(SongModel song) async {
    // If the song is already playing, pause it
    if (_currentSong?.id == song.id && _mp3Player.playing) {
      await _mp3Player.pause();
    }
    // If it's the same song paused, resume
    else if (_currentSong?.id == song.id) {
      await _mp3Player.play();
    }
    // If it's a new song, load and play
    else {
      setState(() {
        _currentSong = song;
      });
      try {
        // Use the song's data path to play the local file
        await _mp3Player.setFilePath(song.data);
        await _mp3Player.play();
      } catch (e) {
        print("Error playing local file: $e");
      }
    }
    setState(() {}); // Trigger rebuild to update play/pause icon
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MP3 Player - Local Files',style: TextStyle(
          fontSize: 25,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),),
        backgroundColor: Colors.blueGrey,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkAndRequestPermissions,
          )
        ],
      ),
      body: !_hasPermission
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Permission to access local storage is required.'),
            ElevatedButton(
              onPressed: _checkAndRequestPermissions,
              child: const Text('Request Permission'),
            ),
          ],
        ),
      )
          : FutureBuilder<List<SongModel>>(
        future: _audioQuery.querySongs(
          sortType: null,
          orderType: OrderType.ASC_OR_SMALLER,
          uriType: UriType.EXTERNAL,
          ignoreCase: true,
        ),
        builder: (context, item) {
          // Loading content indicator
          if (item.connectionState == ConnectionState.waiting || item.data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          // If no songs are found
          if (item.data!.isEmpty) {
            return const Center(child: Text("No MP3 files found on device."));
          }

          // Display the playlist
          return ListView.builder(
            itemCount: item.data!.length,
            itemBuilder: (context, index) {
              final song = item.data![index];
              final isPlaying = _currentSong?.id == song.id && _mp3Player.playing;

              return StreamBuilder<PlayerState>(
                  stream: _mp3Player.playerStateStream,
                  builder: (context, snapshot) {
                    final playerState = snapshot.data;
                    final isCurrentlyPlaying = _currentSong?.id == song.id && playerState?.playing == true;

                    return ListTile(
                      title: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrentlyPlaying ? FontWeight.bold : FontWeight.normal,
                          color: isCurrentlyPlaying ? Colors.blueGrey : Colors.black,
                        ),
                      ),
                      subtitle: Text(song.artist ?? 'Unknown Artist', maxLines: 1),
                      leading: QueryArtworkWidget(
                        id: song.id,
                        type: ArtworkType.AUDIO,
                        nullArtworkWidget: const CircleAvatar(
                          child: Icon(Icons.music_note, color: Colors.blueGrey),
                          backgroundColor: Colors.blueGrey,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          isCurrentlyPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                          color: isCurrentlyPlaying ? Colors.green : Colors.blueGrey,
                        ),
                        onPressed: () => _playSong(song),
                      ),
                      onTap: () => _playSong(song),
                    );
                  }
              );
            },
          );
        },
      ),
      // Optional: Add a Mini-Player for the currently playing MP3 song here.
    );
  }
}