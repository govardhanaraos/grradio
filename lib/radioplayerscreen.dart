import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:grradio/main.dart';
import 'package:grradio/radioplayerhandler.dart';
import 'package:grradio/radiostation.dart';
import 'package:grradio/responsebutton.dart';

class RadioPlayerScreen extends StatefulWidget {
  @override
  State<RadioPlayerScreen> createState() => _RadioPlayerScreenState();
}

class _RadioPlayerScreenState extends State<RadioPlayerScreen> {
  // For older audio_service versions, use AudioService directly
  late AudioHandler _audioHandler;
  bool _isSearching = false;
  // 💡 NEW: State to track if the app is currently recording
  bool _isRecording = false;

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = ''; // The current search query for filtering

  @override
  void initState() {
    super.initState();
    // 💡 FIX: Get the running handler instance
    // Assuming the handler was initialized globally (e.g., in main.dart)
    _audioHandler = globalAudioHandler;
    // 💡 NEW: Initialize filtered list with all stations

    // 💡 NEW: Listen to custom events for recording status changes from the handler
    _audioHandler.customEvent.listen((event) {
      if (event is Map) {
        if (event['event'] == 'record_status') {
          setState(() {
            _isRecording = event['isRecording'] as bool;
          });
          if (event['isRecording'] == false) {
            _showSnackbar('Recording saved to Downloads!', Colors.green);
          }
        } else if (event['event'] == 'permission_denied') {
          // Display the specific error message from the handler
          _showSnackbar(event['message'] as String, Colors.red);
        }
      }
    });

    _searchController.addListener(_updateSearchQuery);
  }

  @override
  void dispose() {
    _searchController.removeListener(_updateSearchQuery);
    _searchController.dispose();
    super.dispose();
  }

  // Computed list for filtered stations
  List<RadioStation> get _filteredStations {
    if (_searchQuery.isEmpty) {
      return allRadioStations; // global list from main.dart
    }
    // Filter by name or genre
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

  // 💡 NEW: Toggle Recording Logic
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
      // Capture the state before calling toggleRecord
      final wasRecording = _isRecording;

      await handler.toggleRecord(mediaItem);

      // If we were NOT recording, and we are now recording, show the "started" message.
      // If permission was denied, the custom event listener will handle the snackbar.
      if (!wasRecording && handler.isRecording) {
        _showSnackbar('Recording started for ${mediaItem.title}!', Colors.blue);
      }
      // If it stops, the handler's customEvent listener updates the UI/Snackbar.
    } catch (e) {
      _showSnackbar(
        'An unexpected error occurred: ${e.toString()}',
        Colors.red,
      );
      print('Error during recording: $e');
    }
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(
          seconds: 4,
        ), // Increased duration for error messages
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      autofocus: true, // Auto-focus when search bar appears
      decoration: InputDecoration(
        hintText: 'Search Stations...',
        border: InputBorder.none,
        hintStyle: const TextStyle(color: Colors.white70),
        prefixIcon: const Icon(Icons.search, color: Colors.white),
        // The 'x' button to close the search bar (as requested)
        suffixIcon: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: _closeSearch, // Call the close search method
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

  // Method to close the search bar and clear query
  void _closeSearch() {
    setState(() {
      _isSearching = false;
      _searchController.clear();
      _searchQuery = '';
      FocusScope.of(context).unfocus(); // Dismiss the keyboard
    });
  }

  void _openSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Toggle title/search bar based on state
        title: _isSearching
            ? _buildSearchBar()
            : const Text(
                'GR Radio',
                style: TextStyle(
                  fontSize: 25,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
        backgroundColor: Colors.blueGrey,
        elevation: 0,
        // In search mode, allow the back button to also close the search bar
        automaticallyImplyLeading: !_isSearching,

        // 💡 NEW: Actions for Record and Search
        actions: [
          // 1. Record Button (Visible when not searching)
          if (!_isSearching)
            IconButton(
              icon: Icon(
                _isRecording ? Icons.fiber_manual_record : Icons.mic,
                color: _isRecording ? Colors.redAccent : Colors.white,
                size: 28,
              ),
              tooltip: _isRecording
                  ? 'Stop Recording (Saves to Downloads)'
                  : 'Start Recording',
              onPressed: _toggleRecording,
            ),
          // 2. Search Button (Toggles search bar)
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: Colors.white,
            ),
            onPressed: _isSearching ? _closeSearch : _openSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(flex: 2, child: _buildNowPlayingSection()),
          Expanded(
            flex: 3,
            child: _buildStationsList(), // Use the updated build method
          ),
        ],
      ),
      // 💡 REMOVED: FloatingActionButton for search is removed as it's now in AppBar
      // floatingActionButton: FloatingActionButton(...)
    );
  }

  // ... (Keep existing _buildNowPlayingSection, _playStation, etc. methods)

  // Existing method modified to use the filtered list
  Widget _buildStationsList() {
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem,
      builder: (context, snapshot) {
        final currentMediaId = snapshot.data?.id;

        // Use _filteredStations for the ListView
        return ListView.builder(
          itemCount: _filteredStations.length,
          itemBuilder: (context, index) {
            final station = _filteredStations[index];
            final isPlaying = currentMediaId == station.id;

            return ListTile(
              // ... existing ListTile content
              title: Text(station.name),
              subtitle: Text(station.language ?? 'Radio Station'),
              leading: station.logoUrl != null
                  ? Container(
                      width: 40.0,
                      height: 40.0,
                      // 1. Explicit Container background (for the requested background)
                      decoration: BoxDecoration(
                        color: Colors.grey[200], // Light grey background
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: Image.network(
                          station.logoUrl!,
                          fit: BoxFit.cover,
                          // 2. Add loading state indicator
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
                          // 3. Add error state fallback
                          errorBuilder: (context, error, stackTrace) {
                            // Display a broken image icon on network failure
                            return Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.red[400],
                                size: 24,
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  : const CircleAvatar(child: Icon(Icons.radio)),
              trailing: StreamBuilder<bool>(
                stream: _audioHandler.playbackState.map(
                  (state) =>
                      state.playing &&
                      currentMediaId == station.id &&
                      state.processingState != AudioProcessingState.loading,
                ),
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  return isPlaying
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isPlaying ? Colors.green : Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isPlaying ? 'LIVE' : 'PAUSED',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : const SizedBox.shrink();
                },
              ),
              onTap: () {
                _playStation(station);
              },
            );
          },
        );
      },
    );
  }

  // radioplayerscreen.dart - Use this corrected method
  void _playStation(RadioStation station) async {
    try {
      // ✅ FIX: Cast the generic AudioHandler to your specific handler
      // to access the custom method
      final handler = _audioHandler as RadioPlayerHandler;
      await handler.playStation(
        station,
      ); // This calls the logic in radioplayerhandler.dart
    } catch (e) {
      print("Error playing station: $e");
    }
  }

  // Existing method for Now Playing section (assuming it was outside the main widget build)
  Widget _buildNowPlayingSection() {
    final double sideLength = RButton().getButtonFontSize() * 1.3;
    final double cornerRadius = 8.0; // Small radius for a rounded-square look
    return StreamBuilder<MediaItem?>(
      stream: _audioHandler.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;

        if (mediaItem == null) {
          return const Center(
            child: Text(
              'Select a station to start playing...',
              style: TextStyle(fontSize: 18, color: Colors.blueGrey),
            ),
          );
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SizedBox(
              width: RButton().getButtonFontSize() * 1.2,
              height: RButton().getButtonFontSize() * 1.2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  cornerRadius,
                ), // Apply rounded corners
                child: Container(
                  color: Colors
                      .blueGrey
                      .shade100, // Background color for the container
                  child: mediaItem.artUri != null
                      ? Image.network(
                          mediaItem.artUri.toString(),
                          fit: BoxFit
                              .cover, // Ensures the image fills the entire square container
                          // Add robust loading indicator
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
                          // Add error state fallback
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.red[400],
                                size:
                                    RButton().getButtonFontSize() *
                                    0.8, // Icon size relative to the box size
                              ),
                            );
                          },
                        )
                      : Center(
                          // Fallback text logic (when artUri is null)
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Text(
                              mediaItem.title[0],
                              style: TextStyle(
                                // Note: This text size seems very small (0.02) based on the original snippet,
                                // you might want to adjust this for better visibility within the square.
                                fontSize: RButton().getButtonFontSize() * 0.02,
                              ),
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            SizedBox(height: RButton().getVerticalPadding() * 0.1),
            Text(
              mediaItem.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: RButton().getButtonFontSize() * 0.4,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              mediaItem.genre ?? 'Radio Stream',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
            ),
            SizedBox(height: RButton().getVerticalPadding() * 0.2),
            StreamBuilder<PlaybackState>(
              stream: _audioHandler.playbackState,
              builder: (context, snapshot) {
                final playing = snapshot.data?.playing ?? false;
                final processingState = snapshot.data?.processingState;
                final isLoading =
                    processingState == AudioProcessingState.loading ||
                    processingState == AudioProcessingState.loading;

                return Padding(
                  padding: EdgeInsets.only(
                    bottom: RButton().getButtonFontSize() * 0.45,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 1. PREVIOUS Button
                      _buildControlButton(
                        icon: Icons.skip_previous,
                        onPressed: isLoading
                            ? null
                            : _audioHandler.skipToPrevious,
                        width: RButton().getButtonFontSize(),
                        height: RButton().getButtonFontSize(),
                        iconSize: RButton().getButtonFontSize() * 0.9,
                      ),

                      SizedBox(width: RButton().getHorizontalPadding() * 0.8),

                      // 2. PLAY/PAUSE Button (Largest)
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (isLoading)
                            const SizedBox(
                              width: 80,
                              height: 80,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.blueAccent,
                              ),
                            ),
                          _buildControlButton(
                            icon: playing ? Icons.pause : Icons.play_arrow,
                            width: RButton().getButtonFontSize() * 1.1,
                            height: RButton().getButtonFontSize() * 1.1,
                            iconSize: RButton().getButtonFontSize(),
                            onPressed: isLoading
                                ? null
                                : playing
                                ? _audioHandler.pause
                                : _audioHandler.play,
                          ),
                        ],
                      ),

                      SizedBox(width: RButton().getHorizontalPadding() * 0.8),

                      // 3. NEXT Button
                      _buildControlButton(
                        icon: Icons.skip_next,
                        onPressed: isLoading ? null : _audioHandler.skipToNext,
                        width: RButton().getButtonFontSize(),
                        height: RButton().getButtonFontSize(),
                        iconSize: RButton().getButtonFontSize() * 0.9,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// Helper function to build the custom control button
Widget _buildControlButton({
  required IconData icon,
  required VoidCallback? onPressed,
  double iconSize = 36.0,
  double width = 64.0,
  double height = 64.0,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        // Set the background color to blueGrey
        backgroundColor: Colors.blueGrey,
        // Define the rectangular shape with rounded corners
        shape: CircleBorder(
          eccentricity: 16, // Adjust corner radius as needed
        ),
        // Removes padding to allow button to fill SizedBox
        padding: EdgeInsets.zero,
        // Elevate button visually
        elevation: 5,
        // Disable overlay color when disabled
        disabledBackgroundColor: Colors.blueAccent.withOpacity(0.5),
      ),
      child: Icon(
        icon,
        size: iconSize,
        // Set icon color to white for better contrast
        color: Colors.white,
      ),
    ),
  );
}
