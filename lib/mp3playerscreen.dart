import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:grradio/main.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

// 💡 Simple model for local recording files (not indexed by MediaStore)
class RecordingFile {
  final int id;
  final String title;
  final String path;
  final int fileSizeInBytes; // Size in bytes
  final DateTime dateCreated; // Date Created
  final Duration duration; // Duration

  RecordingFile({
    required this.id,
    required this.title,
    required this.path,
    required this.fileSizeInBytes,
    required this.dateCreated,
    required this.duration,
  });
}

// 💡 Beautiful MP3 Player Screen - Fully Responsive
class Mp3PlayerScreen extends StatefulWidget {
  final int initialTabIndex;
  const Mp3PlayerScreen({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  _Mp3PlayerScreenState createState() => _Mp3PlayerScreenState();
}

// 💡 FIX: Removed TickerProviderStateMixin as it's not strictly necessary for this implementation
class _Mp3PlayerScreenState extends State<Mp3PlayerScreen>
    with TickerProviderStateMixin {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  //final AudioPlayer _mp3Player = AudioPlayer();
  late AudioPlayer _mp3Player;

  late TabController _tabController;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  SongModel? _currentSong;
  List<SongModel>? _songs;
  int _currentIndex = -1;
  LoopMode _loopMode = LoopMode.off;

  // 💡 FIX: Added missing state variable
  bool _isPlayerExpanded = false;
  String? _recordingsPath;

  List<RecordingFile>? _recordings; // List of recorded radio streams
  bool _isCurrentListRecordings =
      false; // Tracks which list the current song belongs to

  @override
  void initState() {
    super.initState();
    _mp3Player = globalMp3Player;
    _tabController = TabController(
      length: 2, // Total number of tabs (Music and Recordings)
      vsync: this,
      initialIndex: widget.initialTabIndex, // Use the passed index
    );

    _checkAndRequestPermissions();

    _setupPlayerListeners();
    _loadLocalRecordings();
  }

  // Helper to format file size (e.g., 5.2 MB)
  String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) +
        ' ' +
        suffixes[i];
  }

  // Helper to format duration (e.g., 00:05:23)
  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void _setupPlayerListeners() {
    // Listen to player completion to auto-play next song
    _mp3Player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_isCurrentListRecordings) {
          // When a recording finishes, stop and reset the current track state.
          // This prevents the player from trying to auto-advance past the last item.
          _mp3Player.stop();
          if (mounted) {
            setState(() {
              if (_currentSong != null) {
                _currentSong = null;
                _currentIndex = -1;
              }
              // Optionally, you might set the button icon to 'play' here
            });
          }
        }

        if (_loopMode == LoopMode.off && !_isCurrentListRecordings) {
          _playNext();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant Mp3PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTabIndex != oldWidget.initialTabIndex) {
      _tabController.animateTo(widget.initialTabIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    // _mp3Player.dispose();
    super.dispose();
  }

  Future<void> _checkAndRequestPermissions() async {
    setState(() {
      _isCheckingPermission = true;
    });

    bool permissionGranted = false;

    // For Android 13+ (API 33+), we need READ_MEDIA_AUDIO
    if (await Permission.audio.isGranted) {
      permissionGranted = true;
    } else {
      // Request audio permission (Android 13+)
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) {
        permissionGranted = true;
      } else {
        // Fallback to storage permission for older Android versions
        final storageStatus = await Permission.storage.request();
        if (storageStatus.isGranted) {
          permissionGranted = true;
        }
      }
    }

    setState(() {
      _hasPermission = permissionGranted;
      _isCheckingPermission = false;
    });

    // Load songs after permission is granted
    if (permissionGranted) {
      _loadSongs();
    }
  }

  // 💡 NEW: Orchestrator to load both all songs and recordings
  Future<void> _loadSongs() async {
    await _loadAllSongs();
    await _loadLocalRecordings();
  }

  // 💡 REFACTORED: Original logic for loading all songs (MediaStore)
  Future<void> _loadAllSongs() async {
    try {
      final songs = await _audioQuery.querySongs(
        sortType: null,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
        ignoreCase: true,
      );

      if (mounted) {
        setState(() {
          _songs = songs;
        });
      }
    } catch (e) {
      print("Error loading songs: $e");
      if (mounted) {
        setState(() {
          _songs = [];
        });
      }
    }
  }

  // 💡 FIX: Logic for loading recorded files from the app's internal download path

  Future<void> _loadLocalRecordings() async {
    // ... (Directory determination logic remains the same) ...
    Directory? directory;
    final externalDirectories = await getExternalStorageDirectories(
      type: StorageDirectory.downloads,
    );

    if (externalDirectories != null && externalDirectories.isNotEmpty) {
      directory = externalDirectories.first;
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    if (directory == null) {
      setState(() {
        _recordings = [];
      });
      return;
    }

    // 💡 NEW: Use a temporary AudioPlayer for duration metadata
    final tempPlayer = AudioPlayer();
    final List<RecordingFile> loadedRecordings = [];
    int idCounter = 0;

    try {
      // Filter for common audio file extensions
      final files = directory
          .listSync()
          .where(
            (f) =>
                f.path.toLowerCase().endsWith('.aac') ||
                f.path.toLowerCase().endsWith('.mp3') ||
                f.path.toLowerCase().endsWith('.m4a') ||
                f.path.toLowerCase().endsWith('.ts'),
          )
          .toList();

      for (final fileSystemEntity in files) {
        if (fileSystemEntity is File) {
          final File file = fileSystemEntity;

          // --- 1. Get File Stats (Size and Date) ---
          final stat = file.statSync();
          final fileSize = stat.size;
          // Use `stat.changed` or `stat.modified` depending on your needs. `changed` is often safer.
          final dateCreated = stat.changed;

          // --- 2. Get Duration using just_audio ---
          Duration duration = Duration.zero;
          try {
            final result = await tempPlayer.setFilePath(file.path);
            duration = result ?? Duration.zero;
          } catch (e) {
            print("Could not get duration for ${file.path}: $e");
          }

          // --- 3. Extract Name ---
          // Assuming file name format is 'Title_Timestamp.ext'
          String fileName = file.uri.pathSegments.last;
          String title = fileName.split('_').first;
          if (title.isEmpty) {
            title = fileName;
          }

          loadedRecordings.add(
            RecordingFile(
              id: idCounter++,
              title: title,
              path: file.path,
              fileSizeInBytes: fileSize,
              dateCreated: dateCreated,
              duration: duration,
            ),
          );
        }
      }
    } catch (e) {
      print('Error loading local recordings: $e');
    } finally {
      // 💡 IMPORTANT: Dispose of the temporary player
      await tempPlayer.dispose();
    }

    loadedRecordings.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));

    if (mounted) {
      setState(() {
        _recordings = loadedRecordings;
      });
    }
  }

  // 💡 REFACTORED: Unified method to play media (SongModel or RecordingFile)
  void _playMedia({
    required dynamic media,
    required int index,
    required bool isRecording,
  }) async {
    // 1. Determine Title, Path, and a unique ID for the player state
    String title;
    String filePath;
    int id;
    String? artist;
    Uri? artUri;

    if (isRecording) {
      final rec = media as RecordingFile;
      title = rec.title;
      filePath = rec.path;
      id = rec.id;
      artist = 'Recording';
      artUri = Uri.parse('file:///recording_placeholder_art');
    } else {
      final song = media as SongModel;
      title = song.title;
      filePath = song.data;
      id = song.id;
      artist = song.artist;
      artUri = (song.albumId != null && song.albumId! > 0)
          ? Uri.parse('content://media/external/audio/albumart/${song.albumId}')
          : Uri.parse('file:///music_placeholder_art');
    }
    print("artist :$artist,title:$title,filePath:$filePath");
    final SongModel newCurrentSong;
    // 2. Check if already playing the same file (using the file's ID)
    if (_currentSong?.id == id && _mp3Player.playing) {
      await _mp3Player.pause();
    } else if (_currentSong?.id == id) {
      await _mp3Player.play();
    } else {
      // 3. Create a pseudo-SongModel for the UI (MiniPlayer/Sheet)
      // This is necessary because _currentSong is defined as SongModel.
      if (isRecording) {
        // If it's a recording, create a new "pseudo" SongModel for the UI
        final Map<String, dynamic> songData = {
          '_id': id,
          'title': title,
          '_data': filePath,
          'artist': artist,
          'album_id': -1,
          'duration': _mp3Player.duration?.inMilliseconds ?? 0,
        };
        newCurrentSong = SongModel(songData);
      } else {
        // If it's a regular MP3, just use the one we already have!
        newCurrentSong = media as SongModel;
      }

      // 4. Update state for playback
      setState(() {
        _currentSong = newCurrentSong;
        _currentIndex = index;
        _isCurrentListRecordings = isRecording;
      });
      print("File(filePath)");
      try {
        final file = File(filePath);

        if (!await file.exists()) {
          throw Exception('File not found at path: $filePath');
        }

        final fileLength = await file.length();
        print('fileLength:$fileLength');
        if (fileLength < 1024) {
          throw Exception('File is corrupt or too small: $fileLength bytes');
        }
        // 💡 FIX: Use setAudioSource with Uri.file for robust local file playback
        await _mp3Player.setAudioSource(
          AudioSource.uri(
            // Use Uri.file to ensure the path is correctly formatted as a file URI
            Uri.file(filePath),
            tag: MediaItem(
              id: id.toString(),
              title: title,
              artist: artist,
              // Use the determined art URI
              artUri: artUri,
              duration: newCurrentSong.duration == null
                  ? null
                  : Duration(milliseconds: newCurrentSong.duration!),
            ),
          ),
        );

        await _mp3Player.play();
        _showPlayerSheet();
      } catch (e) {
        // Print the exact error and path for clear debugging
        print("Error playing local file: $e. Path used: $filePath");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error playing: $title')));
      }
    }
    setState(() {});
  }

  void _playNext() {
    final list = _isCurrentListRecordings ? _recordings : _songs;
    if (list == null || list.isEmpty) return;

    int nextIndex = (_currentIndex + 1) % list.length;
    final nextMedia = list[nextIndex];

    _playMedia(
      media: nextMedia,
      index: nextIndex,
      isRecording: _isCurrentListRecordings,
    );
  }

  void _playPrevious() {
    final list = _isCurrentListRecordings ? _recordings : _songs;
    if (list == null || list.isEmpty) return;

    int prevIndex = (_currentIndex - 1 + list.length) % list.length;
    final prevMedia = list[prevIndex];

    _playMedia(
      media: prevMedia,
      index: prevIndex,
      isRecording: _isCurrentListRecordings,
    );
  }

  // Toggle Shuffle and Loop Mode
  void _toggleLoopMode() {
    setState(() {
      switch (_loopMode) {
        case LoopMode.off:
          _loopMode = LoopMode.one;
          _mp3Player.setLoopMode(LoopMode.one);
          break;
        case LoopMode.one:
          _loopMode = LoopMode.all;
          _mp3Player.setLoopMode(LoopMode.all);
          break;
        case LoopMode.all:
          _loopMode = LoopMode.off;
          _mp3Player.setLoopMode(LoopMode.off);
          break;
      }
    });
  }

  // 💡 FIX: Added state management for the modal sheet
  void _showPlayerSheet() {
    // Avoid opening a second sheet if already expanded
    if (_isPlayerExpanded == true) return;

    setState(() {
      _isPlayerExpanded = true;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _buildPlayerSheet();
      },
    ).then((_) {
      // 💡 FIX: Reset state when the modal is dismissed
      if (mounted) {
        setState(() {
          _isPlayerExpanded = false;
        });
      }
    });
  }

  // --- WIDGET HELPERS ---

  Widget _buildPlaceholderArt(
    double screenWidth,
    double size,
    bool isRecording,
  ) {
    return Container(
      width: size,
      height: size,
      color: Colors.blueGrey[800],
      child: Center(
        child: Icon(
          isRecording ? Icons.mic : Icons.music_note,
          color: Colors.white70,
          size: screenWidth * 0.1,
        ),
      ),
    );
  }

  // 💡 NEW: Helper to build the permission denied screen
  Widget _buildPermissionDenied(
    double screenWidth,
    double screenHeight,
    double emptyIconSize,
    double emptyTitleSize,
    double emptySubtitleSize,
    double buttonPadding,
    double iconSize,
  ) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_open,
              size: emptyIconSize,
              color: Colors.grey[400],
            ),
            SizedBox(height: screenHeight * 0.03),
            Text(
              'Permission Required',
              style: TextStyle(
                fontSize: emptyTitleSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: screenHeight * 0.015),
            Text(
              'We need access to your audio files to play local music.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: emptySubtitleSize),
            ),
            SizedBox(height: screenHeight * 0.04),
            ElevatedButton.icon(
              onPressed: _checkAndRequestPermissions,
              icon: Icon(Icons.security, size: iconSize * 0.8),
              label: Text(
                'Grant Permission',
                style: TextStyle(fontSize: emptySubtitleSize),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[900],
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: buttonPadding,
                  vertical: screenHeight * 0.02,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(screenWidth * 0.075),
                ),
              ),
            ),
            SizedBox(height: screenHeight * 0.02),
            TextButton(
              onPressed: () => openAppSettings(),
              child: Text(
                'Open Settings',
                style: TextStyle(fontSize: emptySubtitleSize),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper function to show a simple snackbar
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // 1. Delete Logic
  Future<void> _deleteRecording(RecordingFile recording) async {
    try {
      final filePath = recording.path;

      final file = File(filePath);
      if (await file.exists()) {
        // 💡 Stop playback if the file being deleted is currently playing
        if (_isCurrentListRecordings && _currentSong?.data == filePath) {
          await _mp3Player.stop();
          setState(() {
            _currentSong = null;
            _currentIndex = -1;
          });
        }

        await file.delete();
        _showSnackBar("Recording '${recording.title}' deleted successfully.");

        // 💡 Reload the recordings list to update the UI
        _loadLocalRecordings();
      } else {
        _showSnackBar("Error: File not found at path.");
      }
    } catch (e) {
      print("Error deleting recording: $e");
      _showSnackBar("Error deleting recording.");
    }
  }

  // 2. Share Logic
  Future<void> _shareRecording(RecordingFile recording) async {
    try {
      final filePath = recording.path;
      final file = File(filePath);

      if (await file.exists()) {
        // 💡 FINAL FIX: Use the static method Share.shareXFiles().
        // This is the officially recommended, non-deprecated replacement for sharing XFiles.
        await Share.shareXFiles([
          XFile(filePath),
        ], subject: 'Check out my recording: ${recording.title}');
      } else {
        _showSnackBar("Error: File not found for sharing.");
      }
    } catch (e) {
      print("Error sharing recording: $e");
      _showSnackBar("Error initiating share action.");
    }
  }

  // 3. Confirmation Dialog
  Future<void> _confirmAndDelete(RecordingFile recording) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
            'Are you sure you want to delete the recording "${recording.title}"? This cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('DELETE', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      _deleteRecording(recording);
    }
  }

  // 💡 NEW: Helper to build the song/recording list view
  Widget _buildSongList({
    required List? list,
    required bool isRecordingList,
    required IconData emptyIcon,
    required String emptyTitle,
    required String emptySubtitle,
    required Function() onRefresh,
    required double screenWidth,
    required double screenHeight,
    required double cardMargin,
    required double emptyIconSize,
    required double emptyTitleSize,
    required double emptySubtitleSize,
    required double buttonPadding,
    required double iconSize,
  }) {
    if (list == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(emptyIcon, size: emptyIconSize, color: Colors.grey[400]),
              SizedBox(height: screenHeight * 0.03),
              Text(
                emptyTitle,
                style: TextStyle(
                  fontSize: emptyTitleSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: screenHeight * 0.015),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: emptySubtitleSize,
                ),
              ),
              SizedBox(height: screenHeight * 0.04),
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: Icon(Icons.refresh, size: iconSize * 0.8),
                label: Text(
                  'Refresh List',
                  style: TextStyle(fontSize: emptySubtitleSize),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey[900],
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: buttonPadding,
                    vertical: screenHeight * 0.02,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(screenWidth * 0.075),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final listItemHeight = screenHeight * 0.1;
    final albumArtSize = screenWidth * 0.15;
    final cardPadding = screenWidth * 0.03;
    final titleFontSize = screenWidth * 0.04;

    // 💡 FIX 1: Slightly reduced base font size for better fit on small screens
    final subtitleFontSize = screenWidth * 0.028;
    final trailingButtonSize = screenWidth * 0.1;

    return ListView.builder(
      itemCount: list.length,
      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
      itemBuilder: (context, index) {
        final media = list[index];
        // Safely check if media is null before casting or accessing properties
        if (media == null) return const SizedBox.shrink();

        final isMediaStore = !isRecordingList;
        // NOTE: Casting is safe here because list is either List<SongModel> or List<RecordingFile>
        final id = isRecordingList ? media.id : (media as SongModel).id;
        final title = isRecordingList
            ? media.title
            : (media as SongModel).title;

        // 💡 FIX: Initialize all variables with default values before the checks
        String artistOrFileType = 'Unknown Type';
        String sizeDurationLine = 'Size: N/A | Duration: N/A';
        String dateLine = 'Date: N/A';

        if (isRecordingList && media is RecordingFile) {
          // Recording File Logic
          artistOrFileType = 'Recording';
          sizeDurationLine =
              'Size: ${_formatBytes(media.fileSizeInBytes, 1)} | Duration: ${_formatDuration(media.duration)}';
          dateLine =
              'Created: ${DateFormat('MMM dd, yyyy HH:mm').format(media.dateCreated)}';
        } else if (media is SongModel) {
          // MP3 File (SongModel) Logic
          final SongModel song = media;
          artistOrFileType = song.artist ?? 'Unknown Artist';

          // on_audio_query provides size (in bytes) and duration (in milliseconds)
          final sizeInBytes = song.size ?? 0;
          final durationMs = song.duration ?? 0;

          // dateAdded is in seconds
          // NOTE: song.dateAdded is nullable, use a fallback of 0
          final dateAddedSeconds = song.dateAdded ?? 0;
          final dateAdded = dateAddedSeconds > 0
              ? DateTime.fromMillisecondsSinceEpoch(dateAddedSeconds * 1000)
              : DateTime.fromMillisecondsSinceEpoch(
                  0,
                ); // Fallback to epoch start

          sizeDurationLine =
              'Size: ${_formatBytes(sizeInBytes, 1)} | Duration: ${_formatDuration(Duration(milliseconds: durationMs))}';
          dateLine =
              'Added: ${DateFormat('MMM dd, yyyy HH:mm').format(dateAdded)}';
        }

        return StreamBuilder<PlayerState>(
          stream: _mp3Player.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final isCurrentlyPlaying =
                _currentSong?.id == id && playerState?.playing == true;

            return GestureDetector(
              onTap: () => _playMedia(
                media: media,
                index: index,
                isRecording: isRecordingList,
              ),
              child: Container(
                margin: EdgeInsets.symmetric(
                  horizontal: cardMargin,
                  vertical: cardMargin * 0.5,
                ),
                height:
                    listItemHeight *
                    1.5, // Increased height to fit two subtitle lines
                decoration: BoxDecoration(
                  color: isCurrentlyPlaying
                      ? Colors.blueGrey[50]
                      : Colors.white,
                  borderRadius: BorderRadius.circular(screenWidth * 0.0375),
                  border: Border.all(
                    color: isCurrentlyPlaying
                        ? Colors.blueGrey
                        : Colors.grey[200]!,
                    width: isCurrentlyPlaying
                        ? screenWidth * 0.005
                        : screenWidth * 0.0025,
                  ),
                  boxShadow: isCurrentlyPlaying
                      ? [
                          BoxShadow(
                            color: Colors.blueGrey.withOpacity(0.1),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ]
                      : [],
                ),
                child: ListTile(
                  // Decreased vertical padding slightly due to increased subtitle lines
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: cardPadding,
                    vertical: cardPadding * 0.1,
                  ),
                  leading: Hero(
                    tag: 'album_art_$id',
                    child: Container(
                      width: albumArtSize,
                      height: albumArtSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(screenWidth * 0.03),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(screenWidth * 0.03),
                        child: isMediaStore
                            ? QueryArtworkWidget(
                                id: id,
                                type: ArtworkType.AUDIO,
                                artworkFit: BoxFit.cover,
                                nullArtworkWidget: _buildPlaceholderArt(
                                  screenWidth,
                                  albumArtSize,
                                  isRecordingList,
                                ),
                              )
                            : _buildPlaceholderArt(
                                screenWidth,
                                albumArtSize,
                                isRecordingList,
                              ),
                      ),
                    ),
                  ),
                  title: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: isCurrentlyPlaying
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: isCurrentlyPlaying
                            ? Colors.blueGrey[900]
                            : Colors.black87,
                        fontSize: titleFontSize,
                      ),
                    ),
                  ),
                  // 💡 REFACTORED: Use a Column for subtitle to stack all details
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment
                        .start, // Center the content vertically
                    children: [
                      const SizedBox(height: -2),
                      Text(
                        artistOrFileType,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: subtitleFontSize * 1.0,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 1), // Small separator
                      Text(
                        sizeDurationLine,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: subtitleFontSize * 0.9,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        dateLine,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: subtitleFontSize * 0.85,
                        ),
                      ),
                    ],
                  ),
                  trailing: isRecordingList
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            final selectedRecording = list[index];
                            if (value == 'share') {
                              _shareRecording(selectedRecording);
                            } else if (value == 'delete') {
                              _confirmAndDelete(selectedRecording);
                            }
                          },
                          itemBuilder: (BuildContext context) =>
                              <PopupMenuEntry<String>>[
                                const PopupMenuItem<String>(
                                  value: 'share',
                                  child: Row(
                                    children: [
                                      Icon(Icons.share, size: 20),
                                      SizedBox(width: 8),
                                      Text('Share File'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_forever,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Delete File'),
                                    ],
                                  ),
                                ),
                              ],
                          icon: const Icon(Icons.more_vert),
                        )
                      : (isCurrentlyPlaying // Your existing logic for music files
                            ? const Icon(Icons.volume_up, color: Colors.blue)
                            : null),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMiniPlayer() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Mini Player Sizing
    final miniPlayerHeight = screenHeight * 0.1;
    final albumArtSize = screenWidth * 0.12;
    final cardPadding = screenWidth * 0.02;
    final titleFontSize = screenWidth * 0.04;
    final subtitleFontSize = screenWidth * 0.033;
    final controlIconSize = screenWidth * 0.07;

    return StreamBuilder<PlayerState>(
      stream: _mp3Player.playerStateStream,
      builder: (context, snapshot) {
        final playing = snapshot.data?.playing ?? false;

        return GestureDetector(
          // 💡 FIX: Tap to expand the player sheet
          onTap: _isPlayerExpanded ? null : _showPlayerSheet,
          child: Container(
            height: miniPlayerHeight,
            padding: EdgeInsets.symmetric(horizontal: cardPadding * 2),
            decoration: BoxDecoration(
              color: Colors.blueGrey[900],
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                // Album Art/Image
                Padding(
                  padding: EdgeInsets.all(cardPadding),
                  child: Hero(
                    tag: 'album_art_${_currentSong!.id}',
                    child: Container(
                      width: albumArtSize,
                      height: albumArtSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(screenWidth * 0.03),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(screenWidth * 0.03),
                        child: QueryArtworkWidget(
                          id: _currentSong!.id,
                          type: ArtworkType.AUDIO,
                          artworkFit: BoxFit.cover,
                          nullArtworkWidget: _buildPlaceholderArt(
                            screenWidth,
                            albumArtSize,
                            _isCurrentListRecordings,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Song Info
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: screenWidth * 0.02),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentSong!.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: titleFontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: screenHeight * 0.005),
                        Text(
                          _currentSong!.artist ?? 'Unknown Artist',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: subtitleFontSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),

                // Controls
                IconButton(
                  icon: Icon(Icons.skip_previous, color: Colors.white),
                  iconSize: controlIconSize,
                  onPressed: _playPrevious,
                ),
                IconButton(
                  icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  iconSize: controlIconSize * 1.2,
                  onPressed: () {
                    if (playing) {
                      _mp3Player.pause();
                    } else {
                      _mp3Player.play();
                    }
                  },
                ),
                IconButton(
                  icon: Icon(Icons.skip_next, color: Colors.white),
                  iconSize: controlIconSize,
                  onPressed: _playNext,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlayerSheet() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final albumArtSize = screenWidth * 0.75;
    final titleFontSize = screenWidth * 0.06;
    final subtitleFontSize = screenWidth * 0.045;
    final controlIconSize = screenWidth * 0.15;
    final loopIconSize = screenWidth * 0.07;
    final sliderHeight = screenHeight * 0.05;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.5,
      maxChildSize: 1.0,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.blueGrey[900],
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(screenWidth * 0.08),
            ),
          ),
          child: ListView(
            controller: controller,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: screenWidth * 0.15,
                  height: screenHeight * 0.005,
                  margin: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),

              // Album Art
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.125,
                  vertical: screenHeight * 0.02,
                ),
                child: Hero(
                  tag: 'album_art_${_currentSong!.id}',
                  child: Container(
                    width: albumArtSize,
                    height: albumArtSize,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black54,
                          blurRadius: 10,
                          offset: Offset(0, 5),
                        ),
                      ],
                      borderRadius: BorderRadius.circular(screenWidth * 0.05),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(screenWidth * 0.05),
                      child: QueryArtworkWidget(
                        id: _currentSong!.id,
                        type: ArtworkType.AUDIO,
                        artworkFit: BoxFit.cover,
                        nullArtworkWidget: _buildPlaceholderArt(
                          screenWidth,
                          albumArtSize,
                          _isCurrentListRecordings,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Song Info
              Padding(
                padding: EdgeInsets.only(
                  top: screenHeight * 0.03,
                  bottom: screenHeight * 0.01,
                  left: screenWidth * 0.05,
                  right: screenWidth * 0.05,
                ),
                child: Column(
                  children: [
                    Text(
                      _currentSong!.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: screenHeight * 0.01),
                    Text(
                      _currentSong!.artist ?? 'Unknown Artist',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: subtitleFontSize,
                      ),
                    ),
                  ],
                ),
              ),

              // Seek Slider
              StreamBuilder<Duration?>(
                stream: _mp3Player.durationStream,
                builder: (context, durationSnapshot) {
                  final totalDuration = durationSnapshot.data ?? Duration.zero;
                  return StreamBuilder<Duration>(
                    stream: _mp3Player.positionStream,
                    builder: (context, positionSnapshot) {
                      var position = positionSnapshot.data ?? Duration.zero;
                      if (position > totalDuration) {
                        position = totalDuration;
                      }

                      return Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                              overlayColor: Colors.white10,
                              trackHeight: 4.0,
                            ),
                            child: SizedBox(
                              height: sliderHeight,
                              child: Slider(
                                min: 0.0,
                                max: totalDuration.inMilliseconds.toDouble(),
                                value: position.inMilliseconds.toDouble(),
                                onChanged: (value) {
                                  _mp3Player.seek(
                                    Duration(milliseconds: value.round()),
                                  );
                                },
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.1,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: subtitleFontSize * 0.8,
                                  ),
                                ),
                                Text(
                                  _formatDuration(totalDuration),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: subtitleFontSize * 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),

              // Controls
              Padding(
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.02),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Loop Mode Button
                    IconButton(
                      icon: Icon(
                        _loopMode == LoopMode.off
                            ? Icons.repeat
                            : _loopMode == LoopMode.one
                            ? Icons.repeat_one
                            : Icons.repeat_on,
                        color: _loopMode == LoopMode.off
                            ? Colors.white.withOpacity(0.5)
                            : Colors.white,
                      ),
                      iconSize: loopIconSize,
                      onPressed: _toggleLoopMode,
                    ),
                    // Previous Button
                    IconButton(
                      icon: Icon(Icons.skip_previous, color: Colors.white),
                      iconSize: controlIconSize,
                      onPressed: _playPrevious,
                    ),
                    // Play/Pause Button
                    StreamBuilder<PlayerState>(
                      stream: _mp3Player.playerStateStream,
                      builder: (context, snapshot) {
                        final playing = snapshot.data?.playing ?? false;
                        return Container(
                          width: controlIconSize * 1.2,
                          height: controlIconSize * 1.2,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 10,
                                offset: Offset(0, 5),
                              ),
                            ],
                          ),
                          child: IconButton(
                            icon: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              color: Colors.blueGrey[900],
                            ),
                            iconSize: controlIconSize * 0.7,
                            onPressed: () {
                              if (playing) {
                                _mp3Player.pause();
                              } else {
                                _mp3Player.play();
                              }
                            },
                          ),
                        );
                      },
                    ),
                    // Next Button
                    IconButton(
                      icon: Icon(Icons.skip_next, color: Colors.white),
                      iconSize: controlIconSize,
                      onPressed: _playNext,
                    ),
                    // More Options (Placeholder)
                    IconButton(
                      icon: Icon(
                        Icons.more_horiz,
                        color: Colors.white.withOpacity(0.5),
                      ),
                      iconSize: loopIconSize,
                      onPressed: () {
                        // TODO: Implement more options like delete for recordings
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('More options coming soon!')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- BUILD METHOD START ---
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive sizing for main screen
    final appBarFontSize = screenWidth * 0.06;
    final iconSize = screenWidth * 0.06;
    final emptyIconSize = screenWidth * 0.2;
    final emptyTitleSize = screenWidth * 0.055;
    final emptySubtitleSize = screenWidth * 0.04;
    final buttonPadding = screenWidth * 0.08;
    final cardMargin = screenWidth * 0.03;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'MP3 Player',
            style: TextStyle(
              fontSize: appBarFontSize,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.blueGrey[900],
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(Icons.refresh, color: Colors.white),
              iconSize: iconSize,
              onPressed: () {
                if (_hasPermission) {
                  _loadSongs(); // Reloads both lists
                } else {
                  _checkAndRequestPermissions();
                }
              },
            ),
          ],
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white.withOpacity(0.7),
            labelStyle: TextStyle(
              fontSize: screenWidth * 0.045,
              fontWeight: FontWeight.bold,
            ),
            tabs: const [
              Tab(text: 'All Songs'),
              Tab(text: 'Recordings'),
            ],
            controller: _tabController,
          ),
        ),
        backgroundColor: Colors.grey[100],
        body: _isCheckingPermission
            ? const Center(child: CircularProgressIndicator())
            : !_hasPermission
            ? _buildPermissionDenied(
                screenWidth,
                screenHeight,
                emptyIconSize,
                emptyTitleSize,
                emptySubtitleSize,
                buttonPadding,
                iconSize,
              )
            : Column(
                children: [
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        // 1. All Songs Tab
                        _buildSongList(
                          list: _songs,
                          isRecordingList: false,
                          emptyIcon: Icons.music_off,
                          emptyTitle: 'No MP3 files found',
                          emptySubtitle: 'Add some music files to your device',
                          onRefresh: _loadAllSongs,
                          screenWidth: screenWidth,
                          screenHeight: screenHeight,
                          cardMargin: cardMargin,
                          emptyIconSize: emptyIconSize,
                          emptyTitleSize: emptyTitleSize,
                          emptySubtitleSize: emptySubtitleSize,
                          buttonPadding: buttonPadding,
                          iconSize: iconSize,
                        ),
                        // 2. Recordings Tab
                        _buildSongList(
                          list: _recordings,
                          isRecordingList: true,
                          emptyIcon: Icons.mic_off,
                          emptyTitle: 'No Recordings Found',
                          emptySubtitle:
                              'Recordings will appear here after being saved.',
                          onRefresh: _loadLocalRecordings,
                          screenWidth: screenWidth,
                          screenHeight: screenHeight,
                          cardMargin: cardMargin,
                          emptyIconSize: emptyIconSize,
                          emptyTitleSize: emptyTitleSize,
                          emptySubtitleSize: emptySubtitleSize,
                          buttonPadding: buttonPadding,
                          iconSize: iconSize,
                        ),
                      ],
                    ),
                  ),
                  // Mini Player at Bottom
                  // 💡 FIX: Check the expanded state to ensure the Mini Player is hidden when the sheet is open
                  if (_currentSong != null && !_isPlayerExpanded)
                    _buildMiniPlayer(),
                ],
              ),
      ),
    );
  }
}
