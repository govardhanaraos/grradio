import 'dart:async'; // 💡 FIX: Import needed for StreamSubscription

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:grradio/main.dart';
import 'package:grradio/radioplayerhandler.dart';
import 'package:grradio/radiostation.dart';
import 'package:grradio/responsebutton.dart';

class RadioPlayerScreen extends StatefulWidget {
  final Function(bool) onRecordingStatusChanged;
  final dynamic onNavigateToMp3Tab;
  final dynamic onNavigateToRecordings;

  const RadioPlayerScreen({
    Key? key,
    required this.onNavigateToMp3Tab,
    required this.onNavigateToRecordings, // Add this to the constructor
    required this.onRecordingStatusChanged,
  }) : super(key: key);
  @override
  State<RadioPlayerScreen> createState() => _RadioPlayerScreenState();
}

class _RadioPlayerScreenState extends State<RadioPlayerScreen>
    with TickerProviderStateMixin {
  late AudioHandler _audioHandler;
  late AnimationController _animationController;
  late Animation<double> _animation;

  bool _isSearching = false;
  bool _isRecording = false;
  bool _isPlayerExpanded = false;

  // 💡 FIX: Store the subscription for proper disposal
  StreamSubscription? _customEventSubscription;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _audioHandler = globalAudioHandler;

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 3),
    )..repeat(reverse: true);

    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    // 💡 FIX: Store the subscription
    _customEventSubscription = _audioHandler.customEvent.listen((event) {
      if (event is Map) {
        if (event['event'] == 'record_status') {
          setState(() {
            _isRecording = event['isRecording'] as bool;
          });
          widget.onRecordingStatusChanged(_isRecording);
          if (event['isRecording'] == false) {
            _showSnackbar(
              'Recording stopped and saved to **Downloads**!',
              Colors.green,
            );
          }
        } else if (event['event'] == 'permission_denied') {
          _showSnackbar(event['message'] as String, Colors.red);
        }
      }
    });

    _searchController.addListener(_updateSearchQuery);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.removeListener(_updateSearchQuery);
    _searchController.dispose();
    // 💡 FIX: Cancel the subscription
    _customEventSubscription?.cancel();
    super.dispose();
  }

  List<RadioStation> get _filteredStations {
    if (_searchQuery.isEmpty) {
      return allRadioStations;
    }
    return allRadioStations
        .where(
          (station) =>
              station.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (station.language?.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ) ??
                  false),
        )
        .toList();
  }

  void _toggleRecording() async {
    final mediaItem = _audioHandler.mediaItem.value;
    final isPlaying = _audioHandler.playbackState.value.playing;

    if (mediaItem == null || !isPlaying) {
      _showSnackbar(
        'Please play a radio station before recording.',
        Colors.red,
      );
      return;
    }

    try {
      final handler = _audioHandler as RadioPlayerHandler;
      final wasRecording = _isRecording;

      await handler.toggleRecord(mediaItem);

      if (!wasRecording && handler.isRecording) {
        _showSnackbar('Recording started for ${mediaItem.title}!', Colors.blue);
      }
    } catch (e) {
      _showSnackbar(
        'An unexpected error occurred: ${e.toString()}',
        Colors.red,
      );
      print('Error during recording: $e');
    }
  }

  void _showSnackbar(String message, Color color) {
    // 💡 FIX: CRASH FIX - Check if the widget is mounted before accessing context
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Search Stations...',
        border: InputBorder.none,
        hintStyle: const TextStyle(color: Colors.white70),
        prefixIcon: const Icon(Icons.search, color: Colors.white),
        suffixIcon: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _closeSearch,
        ),
      ),
      style: const TextStyle(color: Colors.white, fontSize: 18),
    );
  }

  void _updateSearchQuery() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchQuery = '';
      FocusScope.of(context).unfocus();
    });
  }

  void _openSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _playStation(RadioStation station) async {
    try {
      final handler = _audioHandler as RadioPlayerHandler;
      await handler.playStation(station);
      setState(() {
        _isPlayerExpanded = true;
      });
    } catch (e) {
      print("Error playing station: $e");
    }
  }

  void _togglePlayerSheet() {
    setState(() {
      _isPlayerExpanded = !_isPlayerExpanded;
    });
  }

  void _minimizePlayer() {
    setState(() {
      _isPlayerExpanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: RButton.getAppBarHeight(),
        title: _isSearching
            ? _buildSearchBar()
            : Text(
                'GR Radio',
                style: TextStyle(
                  fontSize: RButton.getLargeFontSize(),
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
        flexibleSpace: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.red,
                    Colors.orange,
                    Colors.yellow,
                    Colors.green,
                    Colors.blue,
                    Colors.indigo,
                    Colors.purple,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  // Optional: Add some animation to the gradient
                  transform: GradientRotation(_animation.value * 3.14 * 2),
                ),
              ),
            );
          },
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: !_isSearching,
        actions: [
          if (!_isSearching)
            IconButton(
              icon: Icon(
                CupertinoIcons.recordingtape,
                color: _isRecording ? Colors.grey : Colors.white,
              ),
              tooltip: 'Open Recordings',
              onPressed: _isRecording
                  ? () {
                      // 💡 FIX: If recording is in progress, block the action and show a message
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Cannot switch to MP3 Player while radio recording is active.',
                          ),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  : () async {
                      await _audioHandler.pause();

                      // 💡 FIX: Use the dedicated navigation callback for Recordings
                      widget.onNavigateToRecordings();
                    },
            ),
          if (!_isSearching)
            IconButton(
              icon: Icon(
                _isSearching ? Icons.close : Icons.search,
                color: Colors.white,
              ),
              onPressed: _isSearching ? _closeSearch : _openSearch,
            ),
        ],
      ),
      body: Column(children: [Expanded(child: _buildStationsList())]),
      // Bottom player sheet
      bottomSheet: _buildPlayerSheet(),
    );
  }

  Widget _buildPlayerSheet() {
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;

        if (mediaItem == null) {
          return const SizedBox.shrink();
        }

        return AnimatedContainer(
          duration: Duration(milliseconds: 300),
          height: _isPlayerExpanded
              ? MediaQuery.of(context).size.height * 0.7
              : RButton.getLargeButtonSize(),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(_isPlayerExpanded ? 20 : 0),
              topRight: Radius.circular(_isPlayerExpanded ? 20 : 0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: _isPlayerExpanded
              ? _buildExpandedPlayer(mediaItem)
              : _buildMiniPlayer(mediaItem),
        );
      },
    );
  }

  Widget _buildExpandedPlayer(MediaItem mediaItem) {
    return Column(
      children: [
        // Header with minimize button
        Container(
          height: RButton.getMediumButtonSize(),
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Now Playing',
                style: TextStyle(
                  fontSize: RButton.getMediumFontSize(),
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
              Spacer(),
              IconButton(
                icon: Icon(Icons.minimize, color: Colors.blueGrey),
                onPressed: _minimizePlayer,
              ),
            ],
          ),
        ),
        Divider(height: 1),

        // Station image and info
        Expanded(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: RButton.getXXLargeImageSize(),
                  height: RButton.getXXLargeImageSize(),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: RButton.getXLargeSpacing(),
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: mediaItem.artUri != null
                        ? Image.network(
                            mediaItem.artUri.toString(),
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.0,
                                  value:
                                      loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.blueGrey[100],
                                child: Center(
                                  child: Icon(
                                    Icons.radio,
                                    size: RButton.getMediumContainerSize(),
                                    color: Colors.blueGrey[300],
                                  ),
                                ),
                              );
                            },
                          )
                        : Container(
                            color: Colors.blueGrey[100],
                            child: Center(
                              child: Icon(
                                Icons.radio,
                                size: RButton.getMediumContainerSize(),
                                color: Colors.blueGrey[300],
                              ),
                            ),
                          ),
                  ),
                ),
                SizedBox(height: RButton.getMediumSpacing()),
                Text(
                  mediaItem.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: RButton.getLargeFontSize(),
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[800],
                  ),
                ),
                SizedBox(height: RButton.getSmallSpacing()),
                Text(
                  mediaItem.genre ?? 'Radio Stream',
                  style: TextStyle(
                    fontSize: RButton.getSmallFontSize(),
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Controls section
        Expanded(
          flex: 2,
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Control buttons
                StreamBuilder<PlaybackState>(
                  stream: _audioHandler.playbackState,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? false;
                    final processingState = snapshot.data?.processingState;
                    final isLoading =
                        processingState == AudioProcessingState.loading;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Previous button
                        _buildControlButton(
                          icon: Icons.skip_previous,
                          onPressed: _isRecording
                              ? null
                              : _audioHandler.skipToPrevious,
                          width: RButton.getControlButtonSize() * 0.8,
                          height: RButton.getControlButtonSize() * 0.8,
                          iconSize: RButton.getControlIconSize() * 0.8,
                          backgroundcolor: Colors.brown[100]!,
                        ),

                        SizedBox(width: RButton.getXLargeSpacing()),

                        // Play/Pause button
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            if (isLoading)
                              SizedBox(
                                width: RButton.getMainControlButtonSize(),
                                height: RButton.getMainControlButtonSize(),
                                child: CircularProgressIndicator(
                                  strokeWidth: 3,
                                  color: Colors.blueAccent,
                                ),
                              ),
                            _buildControlButton(
                              icon: playing ? Icons.pause : Icons.play_arrow,
                              width: RButton.getMainControlButtonSize() * 0.8,
                              height: RButton.getMainControlButtonSize() * 0.8,
                              iconSize: RButton.getMainControlIconSize() * 0.8,
                              onPressed: _isRecording
                                  ? null
                                  : (playing
                                        ? _audioHandler.pause
                                        : _audioHandler.play),
                              backgroundcolor: Colors.brown[100]!,
                            ),
                          ],
                        ),

                        SizedBox(width: RButton.getXLargeSpacing()),

                        // Next button
                        _buildControlButton(
                          icon: Icons.skip_next,
                          onPressed: _isRecording
                              ? null
                              : _audioHandler.skipToNext,
                          width: RButton.getControlButtonSize() * 0.8,
                          height: RButton.getControlButtonSize() * 0.8,
                          iconSize: RButton.getControlButtonSize() * 0.8,
                          backgroundcolor: Colors.brown[100]!,
                        ),
                      ],
                    );
                  },
                ),

                SizedBox(height: RButton.getXLargeSpacing()),

                // Recording and additional buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Record button
                    _buildActionButton(
                      icon: _isRecording
                          ? Icons.stop
                          : Icons.fiber_manual_record,
                      label: _isRecording ? 'Stop Recording' : 'Record',
                      color: _isRecording ? Colors.red : Colors.blueGrey,
                      onPressed: _toggleRecording,
                    ),

                    // Open recordings button
                    _buildActionButton(
                      icon: CupertinoIcons.recordingtape,
                      label: 'Recordings',
                      color: _isRecording ? Colors.grey : Colors.blueGrey,
                      onPressed: _isRecording
                          ? () {
                              // 💡 FIX: If recording is in progress, block the action and show a message
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Cannot switch to MP3 Player while radio recording is active.',
                                  ),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          : () async {
                              await _audioHandler.pause();

                              // 💡 FIX: Use the dedicated navigation callback for Recordings
                              widget.onNavigateToRecordings();
                            },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniPlayer(MediaItem mediaItem) {
    return StreamBuilder<PlaybackState>(
      stream: _audioHandler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        final processingState = snapshot.data?.processingState;
        final isLoading = processingState == AudioProcessingState.loading;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // Station image thumbnail
              Container(
                width: RButton.getActionButtonSize(),
                height: RButton.getActionButtonSize(),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.blueGrey[100],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: mediaItem.artUri != null
                      ? Image.network(
                          mediaItem.artUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Icon(
                                Icons.radio,
                                size: RButton.getActionIconSize(),
                                color: Colors.blueGrey[300],
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Icon(
                            Icons.radio,
                            size: RButton.getActionIconSize(),
                            color: Colors.blueGrey[300],
                          ),
                        ),
                ),
              ),

              SizedBox(width: 12),

              // Station info
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mediaItem.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: RButton.getSmallFontSize(),
                        color: Colors.blueGrey[800],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      mediaItem.genre ?? 'Radio',
                      style: TextStyle(
                        fontSize: RButton.getSmallFontSize(),
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Mini controls
              Row(
                children: [
                  // Previous button
                  IconButton(
                    icon: Icon(
                      Icons.skip_previous,
                      size: RButton.getActionIconSize(),
                    ),
                    onPressed: _isRecording
                        ? null
                        : _audioHandler.skipToPrevious,
                    color: Colors.blueGrey,
                  ),

                  // Play/Pause button
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isLoading)
                        SizedBox(
                          width: RButton.getActionIconSize(),
                          height: RButton.getActionIconSize(),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.blueAccent,
                          ),
                        ),
                      IconButton(
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          size: 24,
                        ),
                        onPressed: _isRecording
                            ? null
                            : (playing
                                  ? _audioHandler.pause
                                  : _audioHandler.play),
                        color: Colors.blueGrey,
                      ),
                    ],
                  ),

                  // Next button
                  IconButton(
                    icon: Icon(
                      Icons.skip_next,
                      size: RButton.getListIconSize(),
                    ),
                    onPressed: _isRecording ? null : _audioHandler.skipToNext,
                    color: Colors.blueGrey,
                  ),

                  // Expand button
                  IconButton(
                    icon: Icon(
                      Icons.expand_less,
                      size: RButton.getListIconSize(),
                    ),
                    onPressed: _togglePlayerSheet,
                    color: Colors.blueGrey,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: RButton.getListItemHeight(),
          height: RButton.getListItemHeight(),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(30),
          ),
          child: IconButton(
            icon: Icon(icon, color: color),
            onPressed: onPressed,
          ),
        ),
        SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback? onPressed,
    double iconSize = 36.0,
    double width = 64.0,
    double height = 64.0,
    Color backgroundcolor = Colors.brown,
  }) {
    return SizedBox(
      width: width,
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundcolor,
          shape: CircleBorder(),
          padding: EdgeInsets.zero,
          elevation: 5,
          disabledBackgroundColor: backgroundcolor.withOpacity(0.3),
        ),
        child: Icon(
          icon,
          size: iconSize,
          color: onPressed == null ? backgroundcolor : Colors.black54,
        ),
      ),
    );
  }

  Widget _buildStationsList() {
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem,
      builder: (context, snapshot) {
        final currentMediaId = snapshot.data?.id;

        return ListView.builder(
          itemCount: _filteredStations.length,
          itemBuilder: (context, index) {
            final station = _filteredStations[index];
            final isPlaying = currentMediaId == station.id;

            return ListTile(
              title: Text(station.name),
              subtitle: Text(station.language ?? 'Radio Station'),
              leading: station.logoUrl != null
                  ? Container(
                      width: RButton.getActionButtonSize(),
                      height: RButton.getActionButtonSize(),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.network(
                          station.logoUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                value:
                                    loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.red[400],
                                size: RButton.getListIconSize(),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  : CircleAvatar(
                      child: Icon(Icons.radio, size: RButton.getListIconSize()),
                    ),
              trailing: isPlaying
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'PLAYING',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: RButton.getExSmallFontSize(),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              onTap: () {
                _playStation(station);
              },
            );
          },
        );
      },
    );
  }
}
