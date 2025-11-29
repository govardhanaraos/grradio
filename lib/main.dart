import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:grradio/handler/mp3playerhandler.dart';
import 'package:grradio/more/more.dart';
import 'package:grradio/mp3download/mp3downloadscreen.dart'; // Add this import
import 'package:grradio/mp3playerscreen.dart';
import 'package:grradio/radioplayerhandler.dart';
import 'package:grradio/radioplayerscreen.dart';
import 'package:grradio/radiostation.dart';
import 'package:grradio/radiostationserviceapi.dart';
import 'package:just_audio/just_audio.dart';

final RadioStationServiceAPI _radioService = RadioStationServiceAPI();
List<RadioStation> allRadioStations = [];

Future<void> loadStations() async {
  try {
    final stations = await _radioService.fetchRadioStations();

    // Now 'allRadioStations' contains the data from MongoDB
    // You can now use this list to initialize your RadioPlayerHandler or UI.
    print('Loaded ${allRadioStations.length} stations from MongoDB.');
    print('Loaded Stations: ${allRadioStations}');

    allRadioStations = stations;
  } catch (e) {
    print('Failed to load radio stations.');
  }
}

// Global audio handlers
late AudioHandler globalRadioAudioHandler;
late AudioPlayer globalMp3Player;
late Mp3PlayerHandler globalMp3QueueService;

// Audio coordination functions
void pauseRadioIfPlaying() {
  if (globalRadioAudioHandler.playbackState.value.playing) {
    globalRadioAudioHandler.pause();
  }
}

void pauseMp3IfPlaying() {
  print('globalMp3Player.playing: ${globalMp3Player.playing}');
  print('inside pauseMp3IfPlaying (Forcing Stop)');
  try {
    globalMp3Player.stop();
    print('globalMp3Player successfully stopped.');
  } catch (e) {
    // Include error handling just in case, though stop() is usually safe.
    print('Error attempting to stop globalMp3Player: $e');
  }
}

void setupAudioSession() async {
  final session = await AudioSession.instance;
  await session.configure(
    const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy:
          AVAudioSessionRouteSharingPolicy.defaultPolicy,
      avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
    ),
  );
}

Future<void> _initAudioHandlers() async {
  setupAudioSession();

  // Initialize MP3 player
  globalMp3Player = AudioPlayer();

  globalRadioAudioHandler = await AudioService.init(
    builder: () => RadioPlayerHandler(stations: allRadioStations),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.yourapp.radio',
      androidNotificationChannelName: 'Radio Streaming',
      androidNotificationChannelDescription:
          'Audio playback for internet radio',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
      preloadArtwork: true,
    ),
  );
  globalMp3QueueService = Mp3PlayerHandler();
  await globalMp3QueueService.init();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Mobile Ads SDK
    await MobileAds.instance.initialize();
    print('✅ Google Mobile Ads initialized successfully');
  } catch (e) {
    print('❌ Failed to initialize Google Mobile Ads: $e');
    // Continue with app initialization even if ads fail
  }

  await loadStations();
  print("allRadioStations:${allRadioStations}");
  // Initialize audio service for radio
  await _initAudioHandlers();

  runApp(RadioApp());
}

class RadioApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GR Radio',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          elevation: 20,
          selectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 11,
          ),
        ),
      ),
      home: MainNavigator(),
    );
  }
}

// 💡 NEW: Main Navigator Widget to handle Bottom Navigation Bar
class MainNavigator extends StatefulWidget {
  @override
  _MainNavigatorState createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> {
  int _selectedIndex = 0;
  int _previousIndex = 0;

  int _mp3SubTabIndex = 0;
  bool _isRecording = false;

  // NEW: Function to navigate directly to the MP3 Recordings tab (Sub-tab 1)
  void _navigateToMp3RecordingsTab() {
    if (_isRecording) return;
    setState(() {
      _mp3SubTabIndex = 1; // Set to Recordings tab
      _selectedIndex = 1; // Switch to the MP3 Player main tab
    });
  }

  void _navigateToMp3Recordings() {
    setState(() {
      _selectedIndex = 1; // Switch main tab to MP3 Player
      _mp3SubTabIndex = 1; // Set MP3 Player sub-tab to Recordings
    });
  }

  void _updateRecordingStatus(bool isRecording) {
    setState(() {
      _isRecording = isRecording;
    });
  }

  // 💡 Define the screens for the navigation (now 4 items)
  List<Widget> get _widgetOptions => <Widget>[
    RadioPlayerScreen(
      onNavigateToMp3Tab: () => _onItemTapped(1),
      onRecordingStatusChanged: _updateRecordingStatus,
      onNavigateToRecordings: _navigateToMp3RecordingsTab,
    ), // Your existing FM Radio screen
    Mp3PlayerScreen(
      key: ValueKey(_mp3SubTabIndex),
      initialTabIndex: _mp3SubTabIndex,
    ),
    Mp3DownloadScreen(), // New MP3 Download screen
    MoreScreen(), // New More screen
  ];

  void _onItemTapped(int index) {
    // Pause audio when switching between radio and MP3 player
    if (_isRecording) return;

    print('index: $index, selectedIndex: $_selectedIndex');
    if (_selectedIndex != index) {
      if (index == 0 && _selectedIndex == 1) {
        // Switching from MP3 to Radio - pause MP3
        pauseMp3IfPlaying();
      } else if (index == 1 && _selectedIndex == 0) {
        // Switching from Radio to MP3 - pause radio
        pauseRadioIfPlaying();
      }
    }

    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;

      if (index == 1) {
        _mp3SubTabIndex = 0;
      }
    });
  }

  // Custom Bottom Navigation Bar Item
  Widget _buildCustomNavItem({
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? _getItemColor(index).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(
                  color: _getItemColor(index).withOpacity(0.3),
                  width: 1.5,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _getItemColor(index).withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _onItemTapped(index),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon with gradient when selected
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                _getItemColor(index),
                                _getItemColor(index).withOpacity(0.7),
                              ],
                            )
                          : null,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? _getItemColor(index)
                          : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Get color for each navigation item
  Color _getItemColor(int index) {
    switch (index) {
      case 0: // FM Radio
        return Colors.blue.shade700;
      case 1: // MP3 Player
        return Colors.purple.shade600;
      case 2: // MP3 Download
        return Colors.green.shade600;
      case 3: // More
        return Colors.orange.shade600;
      default:
        return Colors.blue.shade700;
    }
  }

  // Get icon for each navigation item
  IconData _getItemIcon(int index) {
    switch (index) {
      case 0: // FM Radio
        return Icons.radio;
      case 1: // MP3 Player
        return Icons.music_note;
      case 2: // MP3 Download
        return CupertinoIcons.arrow_down_circle_fill;
      case 3: // More
        return Icons.more_horiz;
      default:
        return Icons.radio;
    }
  }

  // Get label for each navigation item
  String _getItemLabel(int index) {
    switch (index) {
      case 0:
        return 'Radio';
      case 1:
        return 'Player';
      case 2:
        return 'Download';
      case 3:
        return 'More';
      default:
        return 'Radio';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          key: ValueKey<int>(_selectedIndex),
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: Container(
        margin: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 20,
              offset: Offset(0, 5),
              spreadRadius: 2,
            ),
          ],
          border: Border.all(color: Colors.grey.shade200, width: 1),
        ),
        child: Row(
          children: List.generate(4, (index) {
            // Now 4 items
            return _buildCustomNavItem(
              index: index,
              icon: _getItemIcon(index),
              label: _getItemLabel(index),
              isSelected: _selectedIndex == index,
            );
          }),
        ),
      ),
    );
  }
}
