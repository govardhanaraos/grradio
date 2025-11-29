import 'dart:async'; // 💡 FIX: Import needed for StreamSubscription

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:grradio/ads/ad_helper.dart';
import 'package:grradio/ads/banner_ad_widget.dart';
import 'package:grradio/ads/insterstitialadmanager.dart';
import 'package:grradio/ads/rewardedads.dart';
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

  double? _draggedHeight; // Null means use the standard expandedHeight

  // 💡 FIX: Store the subscription for proper disposal
  StreamSubscription? _customEventSubscription;

  final InterstitialAdManager _interstitialAdManager = InterstitialAdManager();
  final RewardedAdManager _rewardedAdManager = RewardedAdManager();

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _interstitialAdManager.loadInterstitialAd();
    _rewardedAdManager.loadRewardedAd();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showInterstitialAfterDelay();
    });
    _audioHandler = globalRadioAudioHandler;

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
    AdHelper.loadRewardedAd();
  }

  void _showInterstitialAfterDelay() {
    Future.delayed(Duration(seconds: 30), () {
      _interstitialAdManager.showInterstitialAd();
    });
  }

  void _showRewardedAdForRecording() {
    _rewardedAdManager.showRewardedAd(
      onReward: (reward) {
        // Grant user extra recording time or features
        _showSnackbar('Reward earned', Colors.green);
      },
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.removeListener(_updateSearchQuery);
    _searchController.dispose();
    // 💡 FIX: Cancel the subscription
    _customEventSubscription?.cancel();
    _interstitialAdManager.dispose();
    _rewardedAdManager.dispose();
    super.dispose();
  }

  List<RadioStation> get _filteredStations {
    if (_searchQuery.isEmpty) {
      return allRadioStations;
    }
    final query = _searchQuery.toLowerCase();

    return allRadioStations
        .where(
          (station) =>
              // Search by Name (e.g., "Akashvani Kanpur")
              station.name.toLowerCase().contains(query) ||
              // Search by State (e.g., "UTTAR PRADESH") - Now correctly mapped to station.state
              (station.state?.toLowerCase().contains(query) ?? false) ||
              // Search by Language (e.g., "Hindi") - Now correctly mapped to station.language
              (station.language?.toLowerCase().contains(query) ?? false) ||
              // Search by Language (e.g., "Hindi") - Now correctly mapped to station.language
              (station.page?.toLowerCase().contains(query) ?? false),
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
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF1976D2), // Primary Blue for Radio tab
                Color(0xFF42A5F5), // Light Blue
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
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
          IconButton(
            icon: const Icon(Icons.star, color: Colors.yellow),
            tooltip: 'Watch Ad for Reward',
            onPressed: () => _showRewardedAdForReward(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildStationsList()),
          BannerAdWidget(),
        ],
      ),
      // Bottom player sheet
      bottomSheet: _buildPlayerSheet(),
    );
  }

  // ... inside _RadioPlayerScreenState

  // 💡 NEW: Logic to show Rewarded Ad
  void _showRewardedAdForReward() {
    AdHelper.showRewardedAd(
      // Callback if the user successfully watches the ad
      onUserEarnedReward: (rewardItem) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'REWARD GRANTED: ${rewardItem.amount} ${rewardItem.type}!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        // Implement logic to actually grant the reward here
        // For example: increase user points, grant temporary premium access, etc.
      },
      // Callback if the ad fails to load or show
      onAdFailed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ad not ready. Try again in a moment.'),
            backgroundColor: Colors.red,
          ),
        );
      },
    );
  }

  // ...
  Widget _buildPlayerSheet() {
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        final isExpanded = _isPlayerExpanded ?? false;

        if (mediaItem == null) {
          return const SizedBox.shrink();
        }

        final screenHeight = MediaQuery.of(context).size.height;
        final double expandedHeight = screenHeight * 0.80;
        final double miniHeight = RButton.getLargeButtonSize();
        final double cornerRadius = 20.0;

        // Determine the current height for the container.
        // Use _draggedHeight during expansion/drag, or the fixed expanded/mini height.
        final currentHeight = isExpanded
            ? _draggedHeight ?? expandedHeight
            : miniHeight;
        // NOTE: _draggedHeight must be a state variable initialized to expandedHeight
        // when the player first expands.

        return AnimatedContainer(
          duration: Duration(milliseconds: 300),
          height: currentHeight, // Use the dynamic currentHeight
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isExpanded ? cornerRadius : 12),
              topRight: Radius.circular(isExpanded ? cornerRadius : 12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: GestureDetector(
            onVerticalDragUpdate: isExpanded
                ? (details) {
                    // --- START: Drag Animation Logic ---
                    // Calculate new height by subtracting the vertical drag delta (downwards drag is positive delta.dy)

                    final rawNewHeight = currentHeight - details.delta.dy;

                    // 1. 🛑 CLAMP THE HEIGHT TO PREVENT NEGATIVE CONSTRAINTS 🛑
                    final clampedNewHeight = rawNewHeight.clamp(
                      miniHeight,
                      expandedHeight,
                    );

                    // Update the state variable to trigger the sheet redraw
                    // You need to call setState in the parent widget here:
                    /* setState(() {
                    _draggedHeight = newHeight.clamp(miniHeight, expandedHeight);
                  });
                  */
                    // --- END: Drag Animation Logic ---
                  }
                : null,

            onVerticalDragEnd: isExpanded
                ? (details) {
                    // --- START: Drag Dismissal Logic ---
                    final double dragThreshold =
                        expandedHeight * 0.5; // Dismiss if dragged past 50%
                    final double velocityThreshold =
                        500; // Dismiss if swiped fast

                    if (currentHeight < dragThreshold ||
                        details.primaryVelocity! > velocityThreshold) {
                      // 1. If dragged past threshold OR swiped fast downwards: Minimize
                      _minimizePlayer();

                      // 2. You must reset _draggedHeight here to null or expandedHeight
                      setState(() {
                        _draggedHeight = null;
                      });
                    } else {
                      // If not minimized, snap back to full expansion
                      setState(() {
                        _draggedHeight = expandedHeight;
                      });
                    }
                    // --- END: Drag Dismissal Logic ---
                  }
                : null,

            onTap: isExpanded
                ? null
                : () {
                    // Your logic here to set _isPlayerExpanded = true
                  },

            child: isExpanded
                ? _buildExpandedPlayer(mediaItem)
                : _buildMiniPlayer(mediaItem),
          ),
        );
      },
    );
  }

  Widget _buildExpandedPlayer(MediaItem mediaItem) {
    return Container(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
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
                    color: Colors.blueGrey[800],
                  ),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.blueGrey[600],
                    size: RButton.getMediumFontSize() * 1.5,
                  ),
                  onPressed: _minimizePlayer,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.blueGrey[100]),

          // Station image and info
          Expanded(
            flex: 3,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: RButton.getXXLargeImageSize() * 1.1,
                    height: RButton.getXXLargeImageSize() * 1.1,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: RButton.getXLargeSpacing() * 1.5,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: mediaItem.artUri != null
                          ? Image.network(
                              mediaItem.artUri.toString(),
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.0,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.blueAccent,
                                            ),
                                        value:
                                            loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                            : null,
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.blueGrey[200],
                                  child: Center(
                                    child: Icon(
                                      Icons.radio,
                                      size: RButton.getMediumContainerSize(),
                                      color: Colors.blueGrey[400],
                                    ),
                                  ),
                                );
                              },
                            )
                          : Container(
                              color: Colors.blueGrey[200],
                              child: Center(
                                child: Icon(
                                  Icons.radio,
                                  size: RButton.getMediumContainerSize(),
                                  color: Colors.blueGrey[400],
                                ),
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: RButton.getXLargeSpacing()),
                  Text(
                    mediaItem.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: RButton.getLargeFontSize() * 1.2,
                      fontWeight: FontWeight.w900,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  SizedBox(height: RButton.getSmallSpacing()),
                  Text(
                    mediaItem.genre ?? 'Radio Stream',
                    style: TextStyle(
                      fontSize: RButton.getMediumFontSize(),
                      color: Colors.grey[500],
                      fontWeight: FontWeight.w500,
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
              padding: EdgeInsets.all(20), // Reduced padding for better fit
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Control buttons - FIXED: Stable layout
                  StreamBuilder<PlaybackState>(
                    stream: _audioHandler.playbackState,
                    builder: (context, snapshot) {
                      final playing = snapshot.data?.playing ?? false;
                      final processingState = snapshot.data?.processingState;
                      final isLoading =
                          processingState == AudioProcessingState.loading;

                      final Color primaryControlColor = Colors.deepOrangeAccent;
                      final Color secondaryControlColor =
                          Colors.deepOrange[50]!;
                      final double mainButtonSize =
                          RButton.getMainControlButtonSize();

                      Widget _buildBeautifulControlButton({
                        required IconData icon,
                        required VoidCallback? onPressed,
                        required double size,
                        required double iconSize,
                        required Color backgroundColor,
                        required Color iconColor,
                      }) {
                        return Container(
                          width: size,
                          height: size,
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            shape: BoxShape.circle,
                            boxShadow: onPressed != null
                                ? [
                                    BoxShadow(
                                      color: backgroundColor.withOpacity(0.5),
                                      blurRadius: 10,
                                      offset: Offset(0, 5),
                                    ),
                                  ]
                                : null,
                          ),
                          child: IconButton(
                            icon: Icon(icon),
                            iconSize: iconSize,
                            color: iconColor,
                            onPressed: onPressed,
                            padding: EdgeInsets.zero,
                          ),
                        );
                      }

                      return Container(
                        height:
                            mainButtonSize *
                            1.2, // Fixed height to prevent shifting
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Previous button
                            _buildBeautifulControlButton(
                              icon: Icons.skip_previous_rounded,
                              onPressed: _isRecording
                                  ? null
                                  : _audioHandler.skipToPrevious,
                              size: mainButtonSize * 0.6,
                              iconSize: mainButtonSize * 0.4,
                              backgroundColor: secondaryControlColor,
                              iconColor: primaryControlColor,
                            ),

                            SizedBox(width: RButton.getXXLargeSpacing()),

                            // Play/Pause button with stable loading indicator
                            Container(
                              width: mainButtonSize, // Fixed width
                              height: mainButtonSize, // Fixed height
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Loading indicator - positioned absolutely
                                  if (isLoading)
                                    Positioned.fill(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 4,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              primaryControlColor.withOpacity(
                                                0.5,
                                              ),
                                            ),
                                      ),
                                    ),
                                  // Play/Pause button - always present
                                  _buildBeautifulControlButton(
                                    icon: playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: mainButtonSize * 0.8,
                                    iconSize: mainButtonSize * 0.5,
                                    onPressed: _isRecording
                                        ? null
                                        : (playing
                                              ? _audioHandler.pause
                                              : _audioHandler.play),
                                    backgroundColor: primaryControlColor,
                                    iconColor: Colors.white,
                                  ),
                                ],
                              ),
                            ),

                            SizedBox(width: RButton.getXXLargeSpacing()),

                            // Next button
                            _buildBeautifulControlButton(
                              icon: Icons.skip_next_rounded,
                              onPressed: _isRecording
                                  ? null
                                  : _audioHandler.skipToNext,
                              size: mainButtonSize * 0.6,
                              iconSize: mainButtonSize * 0.4,
                              backgroundColor: secondaryControlColor,
                              iconColor: primaryControlColor,
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  SizedBox(
                    height: RButton.getLargeSpacing(),
                  ), // Reduced spacing
                  // Recording and additional buttons
                  Wrap(
                    spacing: 20,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      _buildActionButton(
                        icon: _isRecording
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded,
                        label: _isRecording ? 'Stop Recording' : 'Record',
                        color: _isRecording
                            ? Colors.redAccent
                            : Colors.blueGrey,
                        onPressed: _toggleRecording,
                      ),
                      SizedBox(width: RButton.getXLargeSpacing()),
                      _buildActionButton(
                        icon: CupertinoIcons.recordingtape,
                        label: 'Recordings',
                        color: _isRecording ? Colors.grey : Colors.blueGrey,
                        onPressed: _isRecording
                            ? () {
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
      ),
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
              title: Text(
                station.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: RButton.getSmallFontSize(),
                  color: Colors.blueGrey[800],
                ),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(station.language ?? 'Radio Station'),
              leading: station.logoUrl != null
                  ? Container(
                      width: RButton.getActionButtonSize() * 1.5,
                      height: RButton.getActionButtonSize() * 1.5,
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
