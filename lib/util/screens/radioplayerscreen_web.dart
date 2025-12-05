import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:grradio/main.dart';
import 'package:grradio/radiostation.dart';
import 'package:grradio/util/radio_handler_web.dart';

class RadioPlayerScreen extends StatefulWidget {
  final Function(bool) onRecordingStatusChanged;
  final dynamic onNavigateToMp3Tab;
  final dynamic onNavigateToRecordings;

  const RadioPlayerScreen({
    Key? key,
    required this.onNavigateToMp3Tab,
    required this.onNavigateToRecordings,
    required this.onRecordingStatusChanged,
  }) : super(key: key);

  @override
  State<RadioPlayerScreen> createState() => _RadioPlayerScreenState();
}

class _RadioPlayerScreenState extends State<RadioPlayerScreen> {
  final handler = globalRadioAudioHandler as RadioHandlerImpl;

  String _selectedLanguage = 'All';
  bool _isListView = true;
  bool isPlaying = false;

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
  ];

  List<RadioStation> get _filteredStations {
    Iterable<RadioStation> stations = stationsNotifier.value;
    final selected = _selectedLanguage.toLowerCase();

    if (_selectedLanguage != 'All') {
      stations = stations.where((station) {
        final name = station.name.toLowerCase();
        final state = station.state?.toLowerCase() ?? '';
        final language = station.language?.toLowerCase() ?? '';
        final genre = station.genre?.toLowerCase() ?? '';
        final page = station.page?.toLowerCase() ?? '';

        // ✅ Match if any field contains the selected language string
        return name.contains(selected) ||
            language.contains(selected) ||
            genre.contains(selected) ||
            state.contains(selected) ||
            page.contains(selected);
      });
    }

    return stations.toList();
  }

  void _playStation(BuildContext context, RadioStation station) async {
    try {
      await handler.playStation(station);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Playing ${station.name}')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play ${station.name}: $e')),
      );
    }
  }

  Widget _buildControlBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          // Language filter chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _languages.map((lang) {
                  final isSelected = lang == _selectedLanguage;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedLanguage = lang),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blueAccent
                            : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: Colors.blueAccent.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [],
                      ),
                      child: Text(
                        lang,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // View toggle
          IconButton(
            icon: Icon(
              Icons.view_list,
              color: _isListView ? Colors.blueAccent : Colors.grey,
            ),
            onPressed: () => setState(() => _isListView = true),
          ),
          IconButton(
            icon: Icon(
              Icons.grid_view,
              color: !_isListView ? Colors.blueAccent : Colors.grey,
            ),
            onPressed: () => setState(() => _isListView = false),
          ),
        ],
      ),
    );
  }

  Widget _buildStationCard(RadioStation station) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _playStation(context, station),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: station.logoUrl != null && station.logoUrl!.isNotEmpty
                    ? Image.network(
                        station.logoUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      )
                    : const Icon(Icons.radio, size: 60, color: Colors.blueGrey),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      station.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${station.language ?? ''} • ${station.genre ?? ''}",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              // Play button
              StreamBuilder<RadioStation?>(
                stream: handler.currentStationStream,
                builder: (context, snapshot) {
                  final current = snapshot.data;
                  final isCurrent = current?.id == station.id;
                  return IconButton(
                    icon: Icon(
                      isCurrent
                          ? CupertinoIcons.waveform
                          : Icons.play_circle_fill,
                      size: 32,
                      color: isCurrent ? Colors.amber[900] : Colors.blueAccent,
                    ),
                    onPressed: () => _playStation(context, station),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStationGridCard(RadioStation station) {
    return GestureDetector(
      onTap: () => _playStation(context, station),
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            station.logoUrl != null && station.logoUrl!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      station.logoUrl!,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(Icons.radio, size: 60, color: Colors.blueGrey),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                station.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            Flexible(
              child: Text(
                station.language ?? '',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GR Radio (Web)')),
      body: Column(
        children: [
          _buildControlBar(),
          Expanded(
            child: ValueListenableBuilder<List<RadioStation>>(
              valueListenable: stationsNotifier,
              builder: (context, _, __) {
                final stations = _filteredStations;
                if (stations.isEmpty) {
                  return const Center(child: Text('No stations available.'));
                }

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _isListView
                      ? ListView.separated(
                          key: const ValueKey('listView'),
                          padding: const EdgeInsets.all(12),
                          itemCount: stations.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) =>
                              _buildStationCard(stations[index]),
                        )
                      : GridView.builder(
                          key: const ValueKey('gridView'),
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.85,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                          itemCount: stations.length,
                          itemBuilder: (context, index) =>
                              _buildStationGridCard(stations[index]),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
