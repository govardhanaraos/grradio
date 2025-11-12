import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:grradio/mp3playerscreen.dart';
import 'package:grradio/radio_station_service.dart';
import 'package:grradio/radioplayerhandler.dart';
import 'package:grradio/radioplayerscreen.dart';
import 'package:grradio/radiostation.dart';
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
  if (globalMp3Player.playing) {
    globalMp3Player.pause();
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

  // 💡 Define the screens for the navigation
  static final List<Widget> _widgetOptions = <Widget>[
    RadioPlayerScreen(), // Your existing FM Radio screen
    Mp3PlayerScreen(), // The new MP3 Player placeholder screen
  ];

  void _onItemTapped(int index) {
    // Pause audio when switching between radio and MP3 player
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The floating action button (search) from RadioPlayerScreen will no longer
      // be visible here. We will move the search functionality if needed.
      // For now, we only show the body of the selected screen.
      body: Center(child: _widgetOptions.elementAt(_selectedIndex)),
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
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blueGrey.shade700,
        onTap: _onItemTapped,
      ),
    );
  }
}
