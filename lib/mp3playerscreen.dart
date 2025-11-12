import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

// 💡 Beautiful MP3 Player Screen - Fully Responsive
class Mp3PlayerScreen extends StatefulWidget {
  @override
  _Mp3PlayerScreenState createState() => _Mp3PlayerScreenState();
}

class _Mp3PlayerScreenState extends State<Mp3PlayerScreen> {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _mp3Player = AudioPlayer();

  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  SongModel? _currentSong;
  List<SongModel>? _songs;
  int _currentIndex = -1;
  LoopMode _loopMode = LoopMode.off;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();

    // Listen to player completion to auto-play next song
    _mp3Player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _playNext();
      }
    });
  }

  @override
  void dispose() {
    _mp3Player.dispose();
    super.dispose();
  }

  Future<void> _checkAndRequestPermissions() async {
    setState(() {
      _isCheckingPermission = true;
    });

    bool permissionGranted = false;

    if (await Permission.audio.isGranted) {
      permissionGranted = true;
    } else {
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) {
        permissionGranted = true;
      } else {
        final storageStatus = await Permission.storage.request();
        if (storageStatus.isGranted) {
          permissionGranted = true;
        }
      }
    }

    setState(() {
      _hasPermission = permissionGranted;
      _isCheckingPermission = false;
    });

    if (permissionGranted) {
      _loadSongs();
    }
  }

  Future<void> _loadSongs() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      if (mounted) {
        setState(() {
          _songs = songs;
        });
      }
    } catch (e) {
      print("Error loading songs: $e");
      if (mounted) {
        setState(() {
          _songs = [];
        });
      }
    }
  }

  void _playSong(SongModel song, int index) async {
    if (_currentSong?.id == song.id && _mp3Player.playing) {
      await _mp3Player.pause();
    } else if (_currentSong?.id == song.id) {
      await _mp3Player.play();
    } else {
      setState(() {
        _currentSong = song;
        _currentIndex = index;
      });
      try {
        await _mp3Player.setFilePath(song.data);
        await _mp3Player.play();
        _showPlayerSheet();
      } catch (e) {
        print("Error playing local file: $e");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error playing: ${song.title}')));
      }
    }
    setState(() {});
  }

  void _playNext() {
    if (_songs == null || _songs!.isEmpty) return;

    int nextIndex = (_currentIndex + 1) % _songs!.length;
    _playSong(_songs![nextIndex], nextIndex);
  }

  void _playPrevious() {
    if (_songs == null || _songs!.isEmpty) return;

    int prevIndex = (_currentIndex - 1 + _songs!.length) % _songs!.length;
    _playSong(_songs![prevIndex], prevIndex);
  }

  void _toggleLoopMode() {
    setState(() {
      switch (_loopMode) {
        case LoopMode.off:
          _loopMode = LoopMode.all;
          _mp3Player.setLoopMode(LoopMode.all);
          break;
        case LoopMode.all:
          _loopMode = LoopMode.one;
          _mp3Player.setLoopMode(LoopMode.one);
          break;
        case LoopMode.one:
          _loopMode = LoopMode.off;
          _mp3Player.setLoopMode(LoopMode.off);
          break;
      }
    });
  }

  void _showPlayerSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildPlayerSheet(),
    );
  }

  Widget _buildPlayerSheet() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing
    final albumArtSize = screenWidth * 0.7; // 70% of screen width
    final titleFontSize = screenWidth * 0.06; // 6% of screen width
    final artistFontSize = screenWidth * 0.04; // 4% of screen width
    final dragHandleWidth = screenWidth * 0.1;
    final playButtonSize = screenWidth * 0.18;
    final controlIconSize = screenWidth * 0.12;
    final smallIconSize = screenWidth * 0.07;
    final horizontalPadding = screenWidth * 0.06;
    final verticalSpacing = screenHeight * 0.02;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blueGrey[900]!, Colors.blueGrey[700]!],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(screenWidth * 0.075),
              topRight: Radius.circular(screenWidth * 0.075),
            ),
          ),
          child: Column(
            children: [
              // Drag Handle
              Container(
                margin: EdgeInsets.only(top: screenHeight * 0.015),
                width: dragHandleWidth,
                height: screenHeight * 0.006,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(screenWidth * 0.025),
                ),
              ),

              // Close Button
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: Icon(Icons.close, color: Colors.white),
                  iconSize: smallIconSize * 1.2,
                  onPressed: () => Navigator.pop(context),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    children: [
                      SizedBox(height: verticalSpacing),

                      // Album Artwork
                      Hero(
                        tag: 'album_art_${_currentSong?.id}',
                        child: Container(
                          width: albumArtSize,
                          height: albumArtSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              screenWidth * 0.05,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: screenWidth * 0.075,
                                spreadRadius: screenWidth * 0.0125,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              screenWidth * 0.05,
                            ),
                            child: QueryArtworkWidget(
                              id: _currentSong!.id,
                              type: ArtworkType.AUDIO,
                              artworkFit: BoxFit.cover,
                              artworkBorder: BorderRadius.circular(
                                screenWidth * 0.05,
                              ),
                              nullArtworkWidget: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.blueGrey[600]!,
                                      Colors.blueGrey[800]!,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    screenWidth * 0.05,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.music_note,
                                    size: albumArtSize * 0.35,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: verticalSpacing * 2),

                      // Song Title
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Text(
                          _currentSong?.title ?? 'Unknown',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                      SizedBox(height: verticalSpacing * 0.4),

                      // Artist Name
                      Text(
                        _currentSong?.artist ?? 'Unknown Artist',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: artistFontSize,
                        ),
                      ),

                      SizedBox(height: verticalSpacing * 2),

                      // Progress Bar
                      StreamBuilder<Duration?>(
                        stream: _mp3Player.positionStream,
                        builder: (context, snapshot) {
                          final position = snapshot.data ?? Duration.zero;
                          final duration = _mp3Player.duration ?? Duration.zero;

                          return Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: horizontalPadding,
                                ),
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: screenHeight * 0.005,
                                    thumbShape: RoundSliderThumbShape(
                                      enabledThumbRadius: screenWidth * 0.02,
                                    ),
                                    overlayShape: RoundSliderOverlayShape(
                                      overlayRadius: screenWidth * 0.04,
                                    ),
                                  ),
                                  child: Slider(
                                    value: position.inSeconds.toDouble(),
                                    max: duration.inSeconds.toDouble().clamp(
                                      0.0,
                                      double.infinity,
                                    ),
                                    activeColor: Colors.white,
                                    inactiveColor: Colors.white.withOpacity(
                                      0.3,
                                    ),
                                    onChanged: (value) {
                                      _mp3Player.seek(
                                        Duration(seconds: value.toInt()),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: horizontalPadding * 1.3,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: screenWidth * 0.03,
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: screenWidth * 0.03,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),

                      SizedBox(height: verticalSpacing),

                      // Control Buttons
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Loop Button
                            IconButton(
                              icon: Icon(
                                _loopMode == LoopMode.off
                                    ? Icons.repeat
                                    : _loopMode == LoopMode.all
                                    ? Icons.repeat
                                    : Icons.repeat_one,
                                color: _loopMode == LoopMode.off
                                    ? Colors.white.withOpacity(0.5)
                                    : Colors.white,
                              ),
                              iconSize: smallIconSize,
                              onPressed: _toggleLoopMode,
                            ),

                            // Previous Button
                            IconButton(
                              icon: Icon(
                                Icons.skip_previous,
                                color: Colors.white,
                              ),
                              iconSize: controlIconSize,
                              onPressed: _playPrevious,
                            ),

                            // Play/Pause Button
                            StreamBuilder<PlayerState>(
                              stream: _mp3Player.playerStateStream,
                              builder: (context, snapshot) {
                                final playerState = snapshot.data;
                                final playing = playerState?.playing ?? false;
                                final processing =
                                    playerState?.processingState ==
                                        ProcessingState.loading ||
                                    playerState?.processingState ==
                                        ProcessingState.buffering;

                                return Container(
                                  width: playButtonSize,
                                  height: playButtonSize,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [Colors.white, Colors.grey[300]!],
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: screenWidth * 0.0375,
                                        spreadRadius: screenWidth * 0.005,
                                      ),
                                    ],
                                  ),
                                  child: processing
                                      ? Padding(
                                          padding: EdgeInsets.all(
                                            playButtonSize * 0.28,
                                          ),
                                          child: CircularProgressIndicator(
                                            strokeWidth: screenWidth * 0.0075,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.blueGrey[700]!,
                                                ),
                                          ),
                                        )
                                      : IconButton(
                                          icon: Icon(
                                            playing
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            color: Colors.blueGrey[900],
                                          ),
                                          iconSize: playButtonSize * 0.57,
                                          onPressed: () {
                                            if (playing) {
                                              _mp3Player.pause();
                                            } else {
                                              _mp3Player.play();
                                            }
                                          },
                                        ),
                                );
                              },
                            ),

                            // Next Button
                            IconButton(
                              icon: Icon(Icons.skip_next, color: Colors.white),
                              iconSize: controlIconSize,
                              onPressed: _playNext,
                            ),

                            // Shuffle Button
                            IconButton(
                              icon: Icon(
                                Icons.shuffle,
                                color: Colors.white.withOpacity(0.5),
                              ),
                              iconSize: smallIconSize,
                              onPressed: () {
                                // Implement shuffle functionality
                              },
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: verticalSpacing * 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing for main screen
    final appBarFontSize = screenWidth * 0.06;
    final iconSize = screenWidth * 0.06;
    final emptyIconSize = screenWidth * 0.2;
    final emptyTitleSize = screenWidth * 0.055;
    final emptySubtitleSize = screenWidth * 0.04;
    final buttonPadding = screenWidth * 0.08;
    final cardMargin = screenWidth * 0.03;
    final cardPadding = screenWidth * 0.03;
    final listItemHeight = screenHeight * 0.095;
    final albumArtSize = screenWidth * 0.14;
    final titleFontSize = screenWidth * 0.038;
    final subtitleFontSize = screenWidth * 0.033;
    final trailingButtonSize = screenWidth * 0.1;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'MP3 Player',
          style: TextStyle(
            fontSize: appBarFontSize,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey[900],
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            iconSize: iconSize,
            onPressed: () {
              if (_hasPermission) {
                _loadSongs();
              } else {
                _checkAndRequestPermissions();
              }
            },
          ),
        ],
      ),
      backgroundColor: Colors.grey[100],
      body: _isCheckingPermission
          ? const Center(child: CircularProgressIndicator())
          : !_hasPermission
          ? Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.folder_open,
                      size: emptyIconSize,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: screenHeight * 0.03),
                    Text(
                      'Permission Required',
                      style: TextStyle(
                        fontSize: emptyTitleSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    Text(
                      'We need access to your audio files to play local music.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: emptySubtitleSize,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.04),
                    ElevatedButton.icon(
                      onPressed: _checkAndRequestPermissions,
                      icon: Icon(Icons.security, size: iconSize * 0.8),
                      label: Text(
                        'Grant Permission',
                        style: TextStyle(fontSize: emptySubtitleSize),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[900],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: buttonPadding,
                          vertical: screenHeight * 0.02,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            screenWidth * 0.075,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.02),
                    TextButton(
                      onPressed: () => openAppSettings(),
                      child: Text(
                        'Open Settings',
                        style: TextStyle(fontSize: emptySubtitleSize),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _songs == null
          ? const Center(child: CircularProgressIndicator())
          : _songs!.isEmpty
          ? Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.music_off,
                      size: emptyIconSize,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: screenHeight * 0.03),
                    Text(
                      'No MP3 files found',
                      style: TextStyle(
                        fontSize: emptyTitleSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.015),
                    Text(
                      'Add some music files to your device',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: emptySubtitleSize,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.04),
                    ElevatedButton.icon(
                      onPressed: _loadSongs,
                      icon: Icon(Icons.refresh, size: iconSize * 0.8),
                      label: Text(
                        'Refresh',
                        style: TextStyle(fontSize: emptySubtitleSize),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[900],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: buttonPadding * 0.75,
                          vertical: screenHeight * 0.015,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            screenWidth * 0.075,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: _songs!.length,
                    padding: EdgeInsets.symmetric(
                      vertical: screenHeight * 0.01,
                    ),
                    itemBuilder: (context, index) {
                      final song = _songs![index];

                      return StreamBuilder<PlayerState>(
                        stream: _mp3Player.playerStateStream,
                        builder: (context, snapshot) {
                          final playerState = snapshot.data;
                          final isCurrentlyPlaying =
                              _currentSong?.id == song.id &&
                              playerState?.playing == true;

                          return Container(
                            margin: EdgeInsets.symmetric(
                              horizontal: cardMargin,
                              vertical: cardMargin * 0.5,
                            ),
                            height: listItemHeight,
                            decoration: BoxDecoration(
                              color: isCurrentlyPlaying
                                  ? Colors.blueGrey[50]
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(
                                screenWidth * 0.0375,
                              ),
                              border: Border.all(
                                color: isCurrentlyPlaying
                                    ? Colors.blueGrey
                                    : Colors.grey[200]!,
                                width: isCurrentlyPlaying
                                    ? screenWidth * 0.005
                                    : screenWidth * 0.0025,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: cardPadding,
                                vertical: cardPadding * 0.7,
                              ),
                              leading: Hero(
                                tag: 'album_art_${song.id}',
                                child: Container(
                                  width: albumArtSize,
                                  height: albumArtSize,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      screenWidth * 0.03,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      screenWidth * 0.03,
                                    ),
                                    child: QueryArtworkWidget(
                                      id: song.id,
                                      type: ArtworkType.AUDIO,
                                      artworkFit: BoxFit.cover,
                                      nullArtworkWidget: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.blueGrey[300]!,
                                              Colors.blueGrey[500]!,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            screenWidth * 0.03,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.music_note,
                                          color: Colors.white,
                                          size: albumArtSize * 0.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isCurrentlyPlaying
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isCurrentlyPlaying
                                      ? Colors.blueGrey[900]
                                      : Colors.black87,
                                  fontSize: titleFontSize,
                                ),
                              ),
                              subtitle: Text(
                                song.artist ?? 'Unknown Artist',
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: subtitleFontSize,
                                ),
                              ),
                              trailing: Container(
                                width: trailingButtonSize,
                                height: trailingButtonSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isCurrentlyPlaying
                                      ? Colors.blueGrey[900]
                                      : Colors.blueGrey[100],
                                ),
                                child: IconButton(
                                  icon: Icon(
                                    isCurrentlyPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                    color: isCurrentlyPlaying
                                        ? Colors.white
                                        : Colors.blueGrey[900],
                                    size: trailingButtonSize * 0.6,
                                  ),
                                  onPressed: () => _playSong(song, index),
                                ),
                              ),
                              onTap: () => _playSong(song, index),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                // Mini Player at Bottom
                if (_currentSong != null) _buildMiniPlayer(),
              ],
            ),
    );
  }

  Widget _buildMiniPlayer() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final miniPlayerHeight = screenHeight * 0.09;
    final albumArtSize = screenWidth * 0.15;
    final titleFontSize = screenWidth * 0.035;
    final subtitleFontSize = screenWidth * 0.03;
    final iconSize = screenWidth * 0.065;

    return StreamBuilder<PlayerState>(
      stream: _mp3Player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final playing = playerState?.playing ?? false;

        return GestureDetector(
          onTap: _showPlayerSheet,
          child: Container(
            height: miniPlayerHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueGrey[900]!, Colors.blueGrey[700]!],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: screenWidth * 0.025,
                  offset: Offset(0, -screenHeight * 0.0037),
                ),
              ],
            ),
            child: Row(
              children: [
                // Album Art
                Container(
                  width: albumArtSize,
                  height: albumArtSize,
                  margin: EdgeInsets.all(screenWidth * 0.0125),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(screenWidth * 0.02),
                    child: QueryArtworkWidget(
                      id: _currentSong!.id,
                      type: ArtworkType.AUDIO,
                      nullArtworkWidget: Container(
                        color: Colors.blueGrey[600],
                        child: Icon(
                          Icons.music_note,
                          color: Colors.white,
                          size: albumArtSize * 0.5,
                        ),
                      ),
                    ),
                  ),
                ),

                // Song Info
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.03,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentSong!.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: titleFontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: screenHeight * 0.005),
                        Text(
                          _currentSong!.artist ?? 'Unknown Artist',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: subtitleFontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // Controls
                IconButton(
                  icon: Icon(Icons.skip_previous, color: Colors.white),
                  onPressed: _playPrevious,
                ),
                IconButton(
                  icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (playing) {
                      _mp3Player.pause();
                    } else {
                      _mp3Player.play();
                    }
                  },
                ),
                IconButton(
                  icon: Icon(Icons.skip_next, color: Colors.white),
                  onPressed: _playNext,
                ),
                SizedBox(width: screenHeight * 0.01),
              ],
            ),
          ),
        );
      },
    );
  }
}
