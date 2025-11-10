import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:grradio/main.dart';
import 'package:grradio/radio_station_service.dart';
import 'package:grradio/radioplayerhandler.dart';
import 'package:grradio/radiostation.dart';


class RadioPlayerScreen extends StatefulWidget {
  @override
  State<RadioPlayerScreen> createState() => _RadioPlayerScreenState();
}

class _RadioPlayerScreenState extends State<RadioPlayerScreen> {
  // For older audio_service versions, use AudioService directly
  late AudioHandler _audioHandler;
  bool _isSearching = false;

  // 💡 NEW: State for search functionality
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = ''; // The current search query for filtering


  @override
  void initState() {
    super.initState();
    // 💡 FIX: Get the running handler instance
    // Assuming the handler was initialized globally (e.g., in main.dart)
    _audioHandler = globalAudioHandler;
    // 💡 NEW: Initialize filtered list with all stations

    // 💡 NEW: Listen for changes in the text field to filter the stations
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
        .where((station) =>
    station.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (station.genre?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false))
        .toList();
  }


  // Widget for the search input in the AppBar
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
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: _buildNowPlayingSection(),
          ),
          Expanded(
            flex: 3,
            child: _buildStationsList(), // Use the updated build method
          ),
        ],
      ),
      // Search button at bottom right corner (FloatingActionButton as requested)
      floatingActionButton: FloatingActionButton(
        onPressed: _isSearching ? _closeSearch : _openSearch,
        child: Icon(_isSearching ? Icons.close : Icons.search, color: Colors.white,), // 💡 CHANGE: Toggle icon based on state
        backgroundColor: Colors.blueGrey,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat, // Bottom right corner
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
              subtitle: Text(station.genre ?? 'Radio Station'),
              leading: station.logoUrl != null
                  ? CircleAvatar(
                backgroundImage: NetworkImage(station.logoUrl!),
              )
                  : const CircleAvatar(
                child: Icon(Icons.radio),
              ),
              trailing: StreamBuilder<bool>(
                stream: _audioHandler.playbackState.map((state) =>
                state.playing && currentMediaId == station.id && state.processingState != AudioProcessingState.loading),
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data ?? false;
                  return isPlaying
                      ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
      await handler.playStation(station); // This calls the logic in radioplayerhandler.dart
    } catch (e) {
      print("Error playing station: $e");
    }
  }

// Existing method for Now Playing section (assuming it was outside the main widget build)
Widget _buildNowPlayingSection() {
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
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.blueGrey.shade100,
            backgroundImage: mediaItem.artUri != null
                ? NetworkImage(mediaItem.artUri.toString())
                : null,
            child: mediaItem.artUri == null
                ? Text(mediaItem.title[0], style: const TextStyle(fontSize: 40))
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            mediaItem.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          Text(
            mediaItem.genre ?? 'Radio Stream',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          StreamBuilder<PlaybackState>(
            stream: _audioHandler.playbackState,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              final processingState = snapshot.data?.processingState;
              final isLoading = processingState == AudioProcessingState.loading ||
                  processingState == AudioProcessingState.loading;

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    iconSize: 48.0,
                    onPressed: _audioHandler.skipToPrevious,
                  ),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isLoading)
                        const SizedBox(
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      IconButton(
                        icon: Icon(
                          playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        ),
                        iconSize: 64.0,
                        onPressed: isLoading
                            ? null
                            : playing
                            ? _audioHandler.pause
                            : _audioHandler.play,
                        color: Colors.blueGrey,
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    iconSize: 48.0,
                    onPressed: _audioHandler.skipToNext,
                  ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}
}