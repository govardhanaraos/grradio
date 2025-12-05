import 'package:audio_session/audio_session.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:grradio/handler/mp3playerhandler.dart';
import 'package:grradio/more/more.dart';
import 'package:grradio/mp3download/mp3downloadscreen.dart'; // Add this import
import 'package:grradio/mp3playerscreen.dart';
import 'package:grradio/radiostation.dart';
import 'package:grradio/radiostationserviceapi.dart';
import 'package:grradio/util/radioplayerhandler.dart' as handler;
import 'package:grradio/util/screens/miniplayer.dart';
import 'package:grradio/util/screens/radioplayerscreen_stub.dart'
    if (dart.library.io) 'package:grradio/util/screens/radioplayerscreen_mobile.dart'
    if (dart.library.html) 'package:grradio/util/screens/radioplayerscreen_web.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:just_audio/just_audio.dart';

final RadioStationServiceAPI _radioService = RadioStationServiceAPI();
final ValueNotifier<List<RadioStation>> stationsNotifier = ValueNotifier([]);

List<RadioStation> get allRadioStations => stationsNotifier.value;

const int limitPerPage = 50; // Use a consistent limit
bool _isInitializing = false;

Future<void> initializeApp() async {
  // 1. Init Hive
  if (_isInitializing) {
    print(
      "App initialization already in progress or complete. Skipping second call.",
    );
    return;
  }
  _isInitializing = true;

  await Hive.initFlutter();
  Hive.registerAdapter(RadioStationAdapter()); // Generated adapter

  final cachedStationsBox = await Hive.openBox<RadioStation>('cachedStations');
  final List<RadioStation> initialStations = cachedStationsBox.values.toList();
  stationsNotifier.value = initialStations;

  // 3. Start background refresh (non-blocking)
  // 💡 The loadStations is called only once here.
  _loadStationsInBackground(cachedStationsBox);
}

Future<void> _loadStationsInBackground(Box<RadioStation> box) async {
  List<RadioStation> mergedStations = [];
  int currentPage = 1;
  bool hasMore = true;

  print('Starting full station refresh in background...');

  try {
    while (hasMore) {
      final stations = await _radioService.fetchRadioStations(
        page: currentPage,
        limit: limitPerPage,
      );

      mergedStations.addAll(stations);

      print('Loaded Stations page $currentPage: ${stations.length} items');

      if (stations.length < limitPerPage) {
        hasMore = false;
      }
      currentPage++;
    }

    // Update global list and cache only if the fetch was successful
    stationsNotifier.value = mergedStations;
    await box.clear();
    await box.addAll(mergedStations);

    print(
      '✅ Background load complete. Total stations: ${allRadioStations.length}',
    );
  } catch (e) {
    print('Background station refresh failed: $e');
  }
}

Future<void> syncRemoteStations() async {
  try {
    print('🔄 Fetching fresh data from API...');
    // Fetch Page 1
    final firstPage = await _radioService.fetchRadioStations(
      page: 1,
      limit: limitPerPage,
    );

    if (firstPage.isNotEmpty) {
      // Update the UI with fresh data
      stationsNotifier.value = firstPage;
      print("✅ UI Updated with ${firstPage.length} fresh stations.");

      // Kick off background loading for the rest
      _loadRemainingStationsInBackground();
    }
  } catch (e) {
    print("❌ API failed, user is using cached data.");
  }
}

void _loadRemainingStationsInBackground() {
  Future.microtask(() async {
    int currentPage = 2;
    bool hasMore = true;
    List<RadioStation> backgroundStations = [];

    while (hasMore) {
      final stations = await _radioService.fetchRadioStations(
        page: currentPage,
        limit: limitPerPage,
      );

      if (stations.isNotEmpty) {
        backgroundStations.addAll(stations);
        currentPage++;
        if (stations.length < limitPerPage) {
          hasMore = false;
        }
      } else {
        hasMore = false;
      }
    }

    // 3. Merge the background data back into the main list when done
    if (backgroundStations.isNotEmpty) {
      final current = stationsNotifier.value;
      final merged = [...current, ...backgroundStations];

      // Deduplicate by id
      final uniqueStations = {for (var s in merged) s.id: s}.values.toList();

      stationsNotifier.value = uniqueStations;

      print(
        '✅ Background load complete. Total stations: ${stationsNotifier.value.length}',
      );
    }
  });
}

// Global audio handlers
late dynamic globalRadioAudioHandler;
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
  if (kIsWeb) return; // Web has no AVAudioSession; skip
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
  globalMp3Player = AudioPlayer();
  print('kIsWeb : $kIsWeb');

  //if (kIsWeb) {
  // ✅ Web: instantiate directly, no AudioService
  globalRadioAudioHandler = handler.RadioPlayerHandler(
    stations: allRadioStations,
  );
  /* } else {
    // ✅ Mobile: wrap in AudioService
    globalRadioAudioHandler = await AudioService.init(
      builder: () => handler.RadioPlayerHandler(stations: allRadioStations),
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
  }*/

  globalMp3QueueService = await Mp3PlayerHandler();
  globalMp3QueueService.init();
}

void _initializeAdsDelayed() {
  if (kIsWeb) {
    print('Skipping Google Mobile Ads initialization on Web');
    return;
  }

  // Use Future.microtask to ensure this runs immediately after the current event loop finishes,
  // which is after the app has started running (i.e., after runApp()).
  Future.microtask(() async {
    try {
      await MobileAds.instance.initialize();
      print('✅ Google Mobile Ads initialized successfully (Delayed)');
    } catch (e) {
      print('❌ Failed to initialize Google Mobile Ads (Delayed): $e');
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeApp();

  // Initialize audio service for radio
  await _initAudioHandlers();

  runApp(RadioApp());
  _initializeAdsDelayed();
  syncRemoteStations();
  //  _loadRemainingStationsInBackground();
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
      _mp3SubTabIndex = 2; // Set to Recordings tab
      _selectedIndex = 1; // Switch to the MP3 Player main tab
    });
  }

  void _navigateToMp3Recordings() {
    setState(() {
      _selectedIndex = 2; // Switch main tab to MP3 Player
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
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                key: ValueKey<int>(_selectedIndex),
                child: _widgetOptions.elementAt(_selectedIndex),
              ),
            ),
          ),
          // ✅ Conditionally show MiniPlayer only on Web
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kIsWeb) MiniPlayer(handler: globalRadioAudioHandler),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        ],
      ),
    );
  }
}
