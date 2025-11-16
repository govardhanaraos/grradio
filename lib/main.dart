import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:grradio/mp3playerscreen.dart';
import 'package:grradio/radio_station_service.dart';
import 'package:grradio/radioplayerhandler.dart';
import 'package:grradio/radioplayerscreen.dart';
import 'package:grradio/radiostation.dart';
import 'package:grradio/mp3downloadscreen.dart'; // Add this import
import 'package:just_audio/just_audio.dart';

final RadioStationService _radioService = RadioStationService();
List<RadioStation> allRadioStations = [];

Future<void> loadStations() async {
  try {
    allRadioStations = await _radioService.fetchRadioStations();
    // Now 'allRadioStations' contains the data from MongoDB
    // You can now use this list to initialize your RadioPlayerHandler or UI.
    print('Loaded ${allRadioStations.length} stations from MongoDB.');
  } catch (e) {
    print('Failed to load radio stations.');
  }
}

// Global audio handlers
late AudioHandler globalAudioHandler;
late AudioPlayer globalMp3Player;

// Audio coordination functions
void pauseRadioIfPlaying() {
  if (globalAudioHandler.playbackState.value.playing) {
    globalAudioHandler.pause();
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadStations();
  print("allRadioStations:${allRadioStations}");
  // Initialize audio service for radio

  // Initialize audio session
  setupAudioSession();

  // Initialize MP3 player
  globalMp3Player = AudioPlayer();

  globalAudioHandler = await AudioService.init(
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

  runApp(RadioApp());
}

class RadioApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GR Radio',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
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

  // 💡 Define the screens for the navigation
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The floating action button (search) from RadioPlayerScreen will no longer
      // be visible here. We will move the search functionality if needed.
      // For now, we only show the body of the selected screen.
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          // Use a key tied to the index to force AnimatedSwitcher to animate the switch
          key: ValueKey<int>(_selectedIndex),
          child: _widgetOptions.elementAt(_selectedIndex),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.radio), // FM Radio Icon
            label: 'FM Radio',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.music_note), // MP3 Player Icon
            label: 'MP3 Player',
          ),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.arrow_down_circle_fill), // Beautiful Cupertino icon
            label: 'MP3 Download',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blueGrey.shade700,
        unselectedItemColor: _isRecording
            ? Colors.grey
            : Theme.of(context).unselectedWidgetColor,
        onTap: _onItemTapped,
      ),
    );
  }
}
