import 'dart:async'; // 💡 FIX: Import needed for StreamSubscription

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:grradio/ads/ad_helper.dart';
import 'package:grradio/ads/banner_ad_widget.dart';
import 'package:grradio/ads/insterstitialadmanager.dart';
import 'package:grradio/ads/rewardedads.dart';
import 'package:grradio/main.dart';
import 'package:grradio/radiostation.dart';
import 'package:grradio/responsebutton.dart';
import 'package:grradio/util/radio_handler_base.dart';
import 'package:shimmer/shimmer.dart';

typedef RadioPlayerHandler = RadioHandlerBase;

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

  String _selectedLanguage = 'All';
  bool _isListView = true; // true for ListView, false for Icon/GridView

  // 💡 NEW: Define the list of languages/categories
  final List<String> _languages = [
    'All',
    'Telugu',
    'Arabi',
    'Tamil',
    'Hindi',
    'English',
    'Kannada',
    'Malayalam',
    'Punjabi',
    'Bengali',
  ]; // Add more as needed

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
    Iterable<RadioStation> stations = allRadioStations;
    String query = _searchQuery.toLowerCase();
    if (query == 'Arabi') query = 'saudi';

    if (_searchQuery.isNotEmpty) {
      stations = stations.where(
        (station) =>
            station.name.toLowerCase().contains(query) ||
            (station.state?.toLowerCase().contains(query) ?? false) ||
            (station.language?.toLowerCase().contains(query) ?? false) ||
            (station.genre?.toLowerCase().contains(query) ?? false) ||
            (station.page?.toLowerCase().contains(query) ?? false),
      );
    }
    return stations.toList();
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
    final url = station.streamUrl?.trim() ?? '';
    if (url.isEmpty) {
      _showSnackbar('This station has no playable stream URL.', Colors.red);
      return;
    }
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
          if (!_isSearching && !kIsWeb)
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
          //_buildLanguageFilterBar(),
          //_buildViewSwitcherAndCount(),
          _buildControlBar(context),
          Expanded(child: _buildStationsList()),
          BannerAdWidget(),
        ],
      ),
      // Bottom player sheet
      bottomSheet: _buildPlayerSheet(),
    );
  }

  Widget _buildControlBar(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double h = size.height;
    final double w = size.width;

    final double barHeight = h * 0.07;
    final double fontSize = h * 0.018;
    final double iconSize = w * 0.065;
    final double chipHeight = h * 0.045;

    return Container(
      height: barHeight,
      padding: EdgeInsets.symmetric(horizontal: w * 0.02, vertical: h * 0.01),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // LEFT SIDE: Scrollable Language Buttons
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _languages.length,
              separatorBuilder: (ctx, index) => SizedBox(width: w * 0.02),
              itemBuilder: (context, index) {
                final language = _languages[index];
                final isSelected = language == _selectedLanguage;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedLanguage = language;
                    });
                  },
                  child: Container(
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(horizontal: w * 0.04),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blueAccent : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? Colors.blueAccent
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Text(
                      language,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.blueGrey[700],
                        fontSize: fontSize,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // SPACER / DIVIDER
          Container(
            margin: EdgeInsets.symmetric(horizontal: w * 0.02),
            width: 1,
            height: chipHeight * 0.8,
            color: Colors.grey[300],
          ),

          // RIGHT SIDE: View Switcher Icons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // List View Icon
              InkWell(
                onTap: () => setState(() => _isListView = true),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.view_list_rounded,
                    size: iconSize,
                    color: _isListView ? Colors.blueAccent : Colors.grey[400],
                  ),
                ),
              ),
              SizedBox(width: w * 0.01),
              // Grid/Icon View Icon
              InkWell(
                onTap: () => setState(() => _isListView = false),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.grid_view_rounded,
                    size: iconSize,
                    color: !_isListView ? Colors.blueAccent : Colors.grey[400],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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

        final size = MediaQuery.of(context).size;
        final double screenHeight = size.height;
        // 💡 EXPANDED HEIGHT ADJUSTMENT
        final double expandedHeight = screenHeight * 0.80;
        final double miniHeight = screenHeight * 0.1; // ~8-10% for mini player

        final currentHeight = isExpanded
            ? _draggedHeight ?? expandedHeight
            : miniHeight;

        return AnimatedContainer(
          duration: Duration(milliseconds: 300),
          height: currentHeight, // Use the dynamic currentHeight
          decoration: BoxDecoration(
            color: Colors.white, // Ensure white background
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isExpanded ? 20 : 12),
              topRight: Radius.circular(isExpanded ? 20 : 12),
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
                    final rawNewHeight = currentHeight - details.delta.dy;
                    setState(() {
                      _draggedHeight = rawNewHeight.clamp(
                        miniHeight,
                        expandedHeight,
                      );
                    });
                  }
                : null,

            onVerticalDragEnd: isExpanded
                ? (details) {
                    final double dragThreshold = expandedHeight * 0.5;
                    final double velocityThreshold = 500;

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
                    setState(() {
                      _isPlayerExpanded = true;
                      _draggedHeight = expandedHeight;
                    });
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
    final size = MediaQuery.of(context).size;
    final double screenHeight = size.height;
    final double screenWidth = size.width;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // 1. Header (Dynamic Height)
          SizedBox(
            height: screenHeight * 0.08,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.05),
              child: Row(
                children: [
                  Text(
                    'Now Playing',
                    style: TextStyle(
                      fontSize: screenHeight * 0.025,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.blueGrey[600],
                      size: screenHeight * 0.04,
                    ),
                    onPressed: _minimizePlayer,
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: Colors.blueGrey[100]),

          // Station image and info
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Get available dimensions inside the sheet
                final double h = constraints.maxHeight;
                final double w = constraints.maxWidth;

                return Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // ARTWORK (Responsive)
                    Container(
                      height: h * 0.35, // 35% of available sheet height
                      width: h * 0.35, // Keep it square
                      constraints: BoxConstraints(
                        maxHeight: w * 0.8, // Do not exceed 80% width
                        maxWidth: w * 0.8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 15,
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
                                errorBuilder: (_, __, ___) =>
                                    _buildPlaceholderArt(),
                              )
                            : _buildPlaceholderArt(),
                      ),
                    ),

                    // INFO (Title + Genre)
                    SizedBox(
                      height: h * 0.15,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: w * 0.1),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // MARQUEE TITLE (Auto Scrolling)
                            SizedBox(
                              height: h * 0.08,
                              child: MarqueeWidget(
                                child: Text(
                                  mediaItem.title,
                                  style: TextStyle(
                                    fontSize:
                                        screenHeight * 0.03, // Responsive Font
                                    fontWeight: FontWeight.w900,
                                    color: Colors.blueGrey[900],
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: h * 0.01),
                            Text(
                              mediaItem.genre ?? 'Radio Stream',
                              style: TextStyle(
                                fontSize: screenHeight * 0.02,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // CONTROLS & ACTIONS
                    SizedBox(
                      height: h * 0.35, // 35% allocated for buttons
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Playback Icons
                          _buildPlaybackControls(screenHeight, w),

                          Spacer(),

                          // Record Actions
                          _buildBottomActions(screenHeight, w),

                          SizedBox(height: h * 0.05),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderArt() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(Icons.radio, size: 60, color: Colors.grey[400]),
      ),
    );
  }

  // Helper for Controls using MediaQuery
  Widget _buildPlaybackControls(double screenH, double screenW) {
    return StreamBuilder<PlaybackState>(
      stream: _audioHandler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        final processingState = snapshot.data?.processingState;
        final isLoading = processingState == AudioProcessingState.loading;

        final double mainIconSize = screenW * 0.18; // 18% of screen width
        final double sideIconSize = screenW * 0.12; // 12% of screen width

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: Icon(Icons.skip_previous_rounded),
              iconSize: sideIconSize,
              color: Colors.deepOrangeAccent,
              onPressed: _isRecording ? null : _audioHandler.skipToPrevious,
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: mainIconSize,
                    height: mainIconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      color: Colors.deepOrangeAccent,
                    ),
                  ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.deepOrangeAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepOrangeAccent.withOpacity(0.4),
                        blurRadius: 10,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    iconSize: mainIconSize * 0.6,
                    color: Colors.white,
                    onPressed: _isRecording
                        ? null
                        : (playing ? _audioHandler.pause : _audioHandler.play),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.skip_next_rounded),
              iconSize: sideIconSize,
              color: Colors.deepOrangeAccent,
              onPressed: _isRecording ? null : _audioHandler.skipToNext,
            ),
          ],
        );
      },
    );
  }

  // Helper for Bottom Actions (Record)
  Widget _buildBottomActions(double screenH, double screenW) {
    if (kIsWeb) {
      // 💡 Hide recording + recordings buttons on web
      return SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildResponsiveActionButton(
          icon: _isRecording
              ? Icons.stop_rounded
              : Icons.fiber_manual_record_rounded,
          label: _isRecording ? 'Stop' : 'Record',
          color: _isRecording ? Colors.redAccent : Colors.blueGrey,
          onTap: !kIsWeb ? _toggleRecording : () {},
          screenH: screenH,
        ),
        SizedBox(width: screenW * 0.1),
        _buildResponsiveActionButton(
          icon: CupertinoIcons.recordingtape,
          label: 'Recordings',
          color: _isRecording ? Colors.grey : Colors.blueGrey,
          onTap: _isRecording
              ? () {}
              : () async {
                  await _audioHandler.pause();
                  widget.onNavigateToRecordings();
                },
          screenH: screenH,
        ),
      ],
    );
  }

  Widget _buildResponsiveActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    required double screenH,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(screenH * 0.015),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(icon, color: color, size: screenH * 0.03),
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: screenH * 0.015, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPlayer(MediaItem mediaItem) {
    final size = MediaQuery.of(context).size;
    final double screenH = size.height;

    return StreamBuilder<PlaybackState>(
      stream: _audioHandler.playbackState,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;
        final processingState = snapshot.data?.processingState;
        final isLoading = processingState == AudioProcessingState.loading;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Row(
            children: [
              // Station image thumbnail
              Container(
                width: screenH * 0.06,
                height: screenH * 0.06,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[200],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: mediaItem.artUri != null
                      ? Image.network(
                          mediaItem.artUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Icon(Icons.radio, color: Colors.grey),
                        )
                      : Icon(Icons.radio, color: Colors.grey),
                ),
              ),

              SizedBox(width: 12),

              // Station info
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mediaItem.title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: screenH * 0.018,
                        color: Colors.blueGrey[800],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      mediaItem.genre ?? 'Radio',
                      style: TextStyle(
                        fontSize: screenH * 0.016,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isLoading)
                Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (!isLoading)
                IconButton(
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  ),
                  iconSize: screenH * 0.045,
                  color: Colors.blueGrey[800],
                  onPressed: _isRecording
                      ? null
                      : (playing ? _audioHandler.pause : _audioHandler.play),
                ),
              IconButton(
                icon: Icon(Icons.expand_less_rounded),
                iconSize: screenH * 0.04,
                color: Colors.blueGrey[600],
                onPressed: _togglePlayerSheet,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStationsList() {
    final stationsToShow = _filteredStations;
    final size = MediaQuery.of(context).size;

    return ValueListenableBuilder<List<RadioStation>>(
      valueListenable: stationsNotifier, // Imported from main.dart
      builder: (context, stations, child) {
        // 1. Show Skeleton if data is empty (First launch, no cache, slow internet)
        if (stations.isEmpty) {
          return StationSkeletonList();
        }

        // Apply filters locally on the updated list
        final stationsToShow = _applyFilters(stations);

        // Empty Search Result
        if (stationsToShow.isEmpty) {
          return Center(child: Text("No stations found"));
        }

        return StreamBuilder<MediaItem?>(
          stream: _audioHandler.mediaItem,
          builder: (context, snapshot) {
            final currentMediaId = snapshot.data?.id;

            return _isListView
                ? ListView.builder(
                    padding: EdgeInsets.only(
                      bottom: 100,
                    ), // Space for bottom sheet
                    itemCount: stationsToShow.length,
                    itemBuilder: (context, index) {
                      return _buildStationListTile(
                        stationsToShow[index],
                        currentMediaId,
                      );
                    },
                  )
                : GridView.builder(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      100,
                    ), // Space for bottom sheet
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.8, // Adjust ratio for Icon+Text
                    ),
                    itemCount: stationsToShow.length,
                    itemBuilder: (context, index) {
                      return _buildStationGridItem(
                        stationsToShow[index],
                        currentMediaId,
                      );
                    },
                  );
          },
        );
      },
    );
  }

  List<RadioStation> _applyFilters(List<RadioStation> sourceList) {
    Iterable<RadioStation> stations = sourceList;
    String query = _searchQuery.toLowerCase();

    if (_searchQuery.isNotEmpty) {
      stations = stations.where(
        (station) =>
            station.name.toLowerCase().contains(query) ||
            (station.language?.toLowerCase().contains(query) ?? false),
      );
    }

    if (_selectedLanguage != 'All') {
      final selectedLanguageLower = _selectedLanguage.toLowerCase();
      stations = stations.where(
        (station) => (station.language?.toLowerCase() == selectedLanguageLower),
      );
    }
    return stations.toList();
  }

  Widget _buildStationGridItem(RadioStation station, String? currentMediaId) {
    final isPlaying = currentMediaId == station.id;
    final size = MediaQuery.of(context).size;

    return InkWell(
      onTap: () => _playStation(station),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: isPlaying ? Colors.blue[50] : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPlaying ? Colors.blueAccent : Colors.grey[200]!,
            width: isPlaying ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: station.logoUrl != null
                      ? Image.network(
                          station.logoUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              Icon(Icons.radio, color: Colors.grey),
                        )
                      : Icon(
                          Icons.radio,
                          size: size.width * 0.1,
                          color: Colors.grey,
                        ),
                ),
              ),
            ),
            // Text
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                station.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: size.height * 0.015, // Responsive font
                  fontWeight: FontWeight.bold,
                  color: isPlaying ? Colors.blue[800] : Colors.blueGrey[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 💡 NEW: Extracted List Tile Widget (Same logic as existing ListTile)
  Widget _buildStationListTile(RadioStation station, String? currentMediaId) {
    final isPlaying = currentMediaId == station.id;

    return ListTile(
      // The content of your existing ListTile from _buildStationsList
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
                        value: loadingProgress.expectedTotalBytes != null
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
  }
}

// 💡 MARQUEE WIDGET IMPLEMENTATION
class MarqueeWidget extends StatefulWidget {
  final Widget child;
  final Axis direction;
  final Duration animationDuration;
  final Duration pauseDuration;

  const MarqueeWidget({
    Key? key,
    required this.child,
    this.direction = Axis.horizontal,
    this.animationDuration = const Duration(seconds: 4),
    this.pauseDuration = const Duration(seconds: 2),
  }) : super(key: key);

  @override
  _MarqueeWidgetState createState() => _MarqueeWidgetState();
}

class _MarqueeWidgetState extends State<MarqueeWidget> {
  late ScrollController _scrollController;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScrolling());
  }

  void _startScrolling() {
    if (!mounted) return;
    _timer = Timer.periodic(widget.animationDuration + widget.pauseDuration, (
      timer,
    ) async {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        if (maxScroll > 0) {
          await _scrollController.animateTo(
            maxScroll,
            duration: widget.animationDuration,
            curve: Curves.easeOut,
          );
          await Future.delayed(widget.pauseDuration);
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(0.0);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: widget.direction,
      physics: NeverScrollableScrollPhysics(), // Disable user scrolling
      child: widget.child,
    );
  }
}

class StationSkeletonList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 10, // Show 10 dummy items
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Row(
              children: [
                // Circle Skeleton (Logo)
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                SizedBox(width: 16),
                // Text Skeletons
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 12,
                        color: Colors.white,
                      ),
                      SizedBox(height: 8),
                      Container(width: 100, height: 10, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
