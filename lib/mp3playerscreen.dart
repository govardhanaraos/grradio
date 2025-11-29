import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:grradio/ads/banner_ad_widget.dart';
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

// 💡 Model for downloaded MP3 files from Music folder
class DownloadedMp3File {
  final int id;
  final String title;
  final String path;
  final int fileSizeInBytes;
  final DateTime dateCreated;
  final Duration duration;
  final String? artist;

  DownloadedMp3File({
    required this.id,
    required this.title,
    required this.path,
    required this.fileSizeInBytes,
    required this.dateCreated,
    required this.duration,
    this.artist,
  });
}

// 💡 Beautiful MP3 Player Screen - Fully Responsive
class Mp3PlayerScreen extends StatefulWidget {
  final int initialTabIndex;
  const Mp3PlayerScreen({Key? key, this.initialTabIndex = 0}) : super(key: key);

  @override
  _Mp3PlayerScreenState createState() => _Mp3PlayerScreenState();
}

class _Mp3PlayerScreenState extends State<Mp3PlayerScreen>
    with TickerProviderStateMixin {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  late AudioPlayer _mp3Player;

  late TabController _tabController;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  SongModel? _currentSong;
  List<SongModel>? _songs;
  List<DownloadedMp3File>? _downloadedMp3s; // New list for downloaded MP3s
  int _currentIndex = -1;
  LoopMode _loopMode = LoopMode.off;

  bool _isPlayerExpanded = false;
  String? _recordingsPath;

  List<RecordingFile>? _recordings;
  bool _isCurrentListRecordings = false;
  bool _isCurrentListDownloadedMp3s =
      false; // Track if current song is from downloaded MP3s

  @override
  void initState() {
    super.initState();
    _mp3Player = globalMp3Player;
    _tabController = TabController(
      length: 3, // Updated: Added third tab for Downloaded MP3s
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );

    _checkAndRequestPermissions();
    _setupPlayerListeners();
    _loadLocalRecordings();
  }

  String _formatBytes(int bytes, int decimals) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) +
        ' ' +
        suffixes[i];
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void _setupPlayerListeners() {
    _mp3Player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (_isCurrentListRecordings || _isCurrentListDownloadedMp3s) {
          // When a recording or downloaded MP3 finishes, stop and reset
          _mp3Player.stop();
          if (mounted) {
            setState(() {
              if (_currentSong != null) {
                _currentSong = null;
                _currentIndex = -1;
              }
            });
          }
        }

        if (_loopMode == LoopMode.off &&
            !_isCurrentListRecordings &&
            !_isCurrentListDownloadedMp3s) {
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
    super.dispose();
  }

  Future<void> _checkAndRequestPermissions() async {
    setState(() {
      _isCheckingPermission = true;
    });

    bool permissionGranted = false;

    if (await Permission.audio.isGranted) {
      permissionGranted = true;
    } else {
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) {
        permissionGranted = true;
      } else {
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

    if (permissionGranted) {
      _loadSongs();
    }
  }

  Future<void> _loadSongs() async {
    await _loadAllSongs();
    await _loadLocalRecordings();
    await _loadDownloadedMp3s(); // Load downloaded MP3s
  }

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

  // 💡 NEW: Load downloaded MP3s from Music folder
  Future<void> _loadDownloadedMp3s() async {
    try {
      // Get app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${appDir.path}/Music');

      // Create Music directory if it doesn't exist
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      final tempPlayer = AudioPlayer();
      final List<DownloadedMp3File> loadedMp3s = [];
      int idCounter = 0;

      // List all files in Music directory
      final files = musicDir.listSync().where((f) {
        final path = f.path.toLowerCase();
        return path.endsWith('.mp3') ||
            path.endsWith('.aac') ||
            path.endsWith('.m4a');
      }).toList();

      for (final fileSystemEntity in files) {
        if (fileSystemEntity is File) {
          final File file = fileSystemEntity;
          final stat = file.statSync();
          final fileSize = stat.size;
          final dateCreated = stat.changed;

          // Extract filename without extension
          String fileName = file.uri.pathSegments.last;
          String title = fileName;
          if (fileName.contains('.')) {
            title = fileName.substring(0, fileName.lastIndexOf('.'));
          }

          // Try to extract artist from filename (format: Artist - Title.mp3)
          String? artist;
          if (title.contains(' - ')) {
            final parts = title.split(' - ');
            if (parts.length >= 2) {
              artist = parts[0];
              title = parts.sublist(1).join(' - ');
            }
          }

          // Get duration
          Duration duration = Duration.zero;
          try {
            final result = await tempPlayer.setFilePath(file.path);
            duration = result ?? Duration.zero;
          } catch (e) {
            print("Could not get duration for ${file.path}: $e");
          }

          loadedMp3s.add(
            DownloadedMp3File(
              id: idCounter++,
              title: title,
              path: file.path,
              fileSizeInBytes: fileSize,
              dateCreated: dateCreated,
              duration: duration,
              artist: artist,
            ),
          );
        }
      }

      // Sort by date created (newest first)
      loadedMp3s.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));

      if (mounted) {
        setState(() {
          _downloadedMp3s = loadedMp3s;
        });
      }

      await tempPlayer.dispose();
    } catch (e) {
      print('Error loading downloaded MP3s: $e');
      if (mounted) {
        setState(() {
          _downloadedMp3s = [];
        });
      }
    }
  }

  Future<void> _loadLocalRecordings() async {
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

    final tempPlayer = AudioPlayer();
    final List<RecordingFile> loadedRecordings = [];
    int idCounter = 0;

    try {
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
          final stat = file.statSync();
          final fileSize = stat.size;
          final dateCreated = stat.changed;

          Duration duration = Duration.zero;
          try {
            final result = await tempPlayer.setFilePath(file.path);
            duration = result ?? Duration.zero;
          } catch (e) {
            print("Could not get duration for ${file.path}: $e");
          }

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
      await tempPlayer.dispose();
    }

    loadedRecordings.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));

    if (mounted) {
      setState(() {
        _recordings = loadedRecordings;
      });
    }
  }

  // 💡 UPDATED: Unified method to play media from all sources
  void _playMedia({
    required dynamic media,
    required int index,
    required bool isRecording,
    required bool isDownloadedMp3,
  }) async {
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
    } else if (isDownloadedMp3) {
      final mp3 = media as DownloadedMp3File;
      title = mp3.title;
      filePath = mp3.path;
      id = mp3.id;
      artist = mp3.artist ?? 'Unknown Artist';
      artUri = Uri.parse('file:///downloaded_mp3_placeholder_art');
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

    if (_currentSong?.id == id && _mp3Player.playing) {
      await _mp3Player.pause();
    } else if (_currentSong?.id == id) {
      await _mp3Player.play();
    } else {
      if (isRecording || isDownloadedMp3) {
        // Create pseudo-SongModel for recordings and downloaded MP3s
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
        newCurrentSong = media as SongModel;
      }

      setState(() {
        _currentSong = newCurrentSong;
        _currentIndex = index;
        _isCurrentListRecordings = isRecording;
        _isCurrentListDownloadedMp3s = isDownloadedMp3;
      });

      print("Playing file: $filePath");
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

        await _mp3Player.setAudioSource(
          AudioSource.uri(
            Uri.file(filePath),
            tag: MediaItem(
              id: id.toString(),
              title: title,
              artist: artist,
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
        print("Error playing local file: $e. Path used: $filePath");
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error playing: $title')));
      }
    }
    setState(() {});
  }

  void _playNext() {
    List? list;
    if (_isCurrentListRecordings) {
      list = _recordings;
    } else if (_isCurrentListDownloadedMp3s) {
      list = _downloadedMp3s;
    } else {
      list = _songs;
    }

    if (list == null || list.isEmpty) return;

    int nextIndex = (_currentIndex + 1) % list.length;
    final nextMedia = list[nextIndex];

    _playMedia(
      media: nextMedia,
      index: nextIndex,
      isRecording: _isCurrentListRecordings,
      isDownloadedMp3: _isCurrentListDownloadedMp3s,
    );
  }

  void _playPrevious() {
    List? list;
    if (_isCurrentListRecordings) {
      list = _recordings;
    } else if (_isCurrentListDownloadedMp3s) {
      list = _downloadedMp3s;
    } else {
      list = _songs;
    }

    if (list == null || list.isEmpty) return;

    int prevIndex = (_currentIndex - 1 + list.length) % list.length;
    final prevMedia = list[prevIndex];

    _playMedia(
      media: prevMedia,
      index: prevIndex,
      isRecording: _isCurrentListRecordings,
      isDownloadedMp3: _isCurrentListDownloadedMp3s,
    );
  }

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

  void _showPlayerSheet() {
    if (_isPlayerExpanded) return;

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
  Future<void> _confirmAndDeleteOld(RecordingFile recording) async {
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
    required bool isDownloadedMp3List,
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
    final albumArtSize = screenWidth * 0.30;
    final cardPadding = screenWidth * 0.03;
    final titleFontSize = screenWidth * 0.04;
    final subtitleFontSize = screenWidth * 0.028;
    final trailingButtonSize = screenWidth * 0.1;

    return ListView.builder(
      itemCount: list.length,
      padding: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
      itemBuilder: (context, index) {
        final media = list[index];
        if (media == null) return const SizedBox.shrink();

        final isMediaStore = !isRecordingList && !isDownloadedMp3List;
        final id = isMediaStore ? (media as SongModel).id : media.id;
        final title = isMediaStore ? (media as SongModel).title : media.title;

        String artistOrFileType = 'Unknown Type';
        String sizeDurationLine = 'Size: N/A | Duration: N/A';
        String dateLine = 'Date: N/A';

        if (isRecordingList && media is RecordingFile) {
          artistOrFileType = 'Recording';
          sizeDurationLine =
              'Size: ${_formatBytes(media.fileSizeInBytes, 1)} | Duration: ${_formatDuration(media.duration)}';
          dateLine =
              'Created: ${DateFormat('MMM dd, yyyy HH:mm').format(media.dateCreated)}';
        } else if (isDownloadedMp3List && media is DownloadedMp3File) {
          artistOrFileType = media.artist ?? 'Downloaded MP3';
          sizeDurationLine =
              'Size: ${_formatBytes(media.fileSizeInBytes, 1)} | Duration: ${_formatDuration(media.duration)}';
          dateLine =
              'Downloaded: ${DateFormat('MMM dd, yyyy HH:mm').format(media.dateCreated)}';
        } else if (media is SongModel) {
          final SongModel song = media;
          artistOrFileType = song.artist ?? 'Unknown Artist';
          final sizeInBytes = song.size ?? 0;
          final durationMs = song.duration ?? 0;
          final dateAddedSeconds = song.dateAdded ?? 0;
          final dateAdded = dateAddedSeconds > 0
              ? DateTime.fromMillisecondsSinceEpoch(dateAddedSeconds * 1000)
              : DateTime.fromMillisecondsSinceEpoch(0);

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
                isDownloadedMp3: isDownloadedMp3List,
              ),
              child: Container(
                margin: EdgeInsets.symmetric(
                  horizontal: cardMargin,
                  vertical: cardMargin * 0.2,
                ),
                height: listItemHeight * 1.5,
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 6.0,
                  ),
                  leading: SizedBox(
                    width: albumArtSize * 0.9,
                    height: albumArtSize * 5.9,
                    child: Hero(
                      tag: 'album_art_$id',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(screenWidth * 0.03),
                        child: isMediaStore
                            ? QueryArtworkWidget(
                                id: id,
                                type: ArtworkType.AUDIO,
                                artworkFit: BoxFit.cover,
                                nullArtworkWidget: _buildPlaceholderArt(
                                  screenWidth,
                                  albumArtSize * 0.9,
                                  isRecordingList || isDownloadedMp3List,
                                ),
                              )
                            : _buildPlaceholderArt(
                                screenWidth,
                                albumArtSize * 0.9,
                                isRecordingList || isDownloadedMp3List,
                              ),
                      ),
                    ),
                  ),
                  title: Text(
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(
                        artistOrFileType,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.grey[800],
                          fontSize: subtitleFontSize * 1.0,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 1),
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
                  trailing: isRecordingList || isDownloadedMp3List
                      ? PopupMenuButton<String>(
                          onSelected: (value) {
                            final selectedFile = list[index];
                            if (value == 'share') {
                              _shareFile(selectedFile);
                            } else if (value == 'delete') {
                              _confirmAndDelete(selectedFile, isRecordingList);
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
                      : (isCurrentlyPlaying
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

  // 💡 NEW: Unified file sharing
  Future<void> _shareFile(dynamic file) async {
    try {
      String filePath;
      String title;

      if (file is RecordingFile) {
        filePath = file.path;
        title = file.title;
      } else if (file is DownloadedMp3File) {
        filePath = file.path;
        title = file.title;
      } else {
        return;
      }

      final fileObj = File(filePath);
      if (await fileObj.exists()) {
        await Share.shareXFiles([
          XFile(filePath),
        ], subject: 'Check out: $title');
      } else {
        _showSnackBar("Error: File not found for sharing.");
      }
    } catch (e) {
      print("Error sharing file: $e");
      _showSnackBar("Error initiating share action.");
    }
  }

  // 💡 UPDATED: Unified delete confirmation
  Future<void> _confirmAndDelete(dynamic file, bool isRecording) async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final fileName = isRecording
            ? (file as RecordingFile).title
            : (file as DownloadedMp3File).title;
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: Text(
            'Are you sure you want to delete "$fileName"? This cannot be undone.',
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
      _deleteFile(file, isRecording);
    }
  }

  // 💡 UPDATED: Unified file deletion
  Future<void> _deleteFile(dynamic file, bool isRecording) async {
    try {
      String filePath;
      String title;

      if (isRecording && file is RecordingFile) {
        filePath = file.path;
        title = file.title;
      } else if (file is DownloadedMp3File) {
        filePath = file.path;
        title = file.title;
      } else {
        return;
      }

      final fileObj = File(filePath);
      if (await fileObj.exists()) {
        // Stop playback if this file is currently playing
        if ((_isCurrentListRecordings && isRecording) ||
            (_isCurrentListDownloadedMp3s && !isRecording)) {
          if (_currentSong?.data == filePath) {
            await _mp3Player.stop();
            setState(() {
              _currentSong = null;
              _currentIndex = -1;
            });
          }
        }

        await fileObj.delete();
        _showSnackBar("'$title' deleted successfully.");

        // Reload the appropriate list
        if (isRecording) {
          _loadLocalRecordings();
        } else {
          _loadDownloadedMp3s();
        }
      } else {
        _showSnackBar("Error: File not found at path.");
      }
    } catch (e) {
      print("Error deleting file: $e");
      _showSnackBar("Error deleting file.");
    }
  }

  // Rest of the methods remain the same (_buildPlaceholderArt, _buildPermissionDenied,
  // _showSnackBar, _buildMiniPlayer, _buildPlayerSheet, etc.)

  // ... [Keep all the existing _buildPlaceholderArt, _buildPermissionDenied,
  // _showSnackBar, _buildMiniPlayer, _buildPlayerSheet methods exactly as they are] ...

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final appBarFontSize = screenWidth * 0.06;
    final iconSize = screenWidth * 0.06;
    final emptyIconSize = screenWidth * 0.2;
    final emptyTitleSize = screenWidth * 0.055;
    final emptySubtitleSize = screenWidth * 0.04;
    final buttonPadding = screenWidth * 0.08;
    final cardMargin = screenWidth * 0.03;

    return DefaultTabController(
      length: 3, // Updated to 3 tabs
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
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF7B1FA2), // Deep Purple
                  Color(0xFFBA68C8), // Light Purple
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
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
                  _loadSongs(); // Reloads all three lists
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
              Tab(text: 'Downloaded MP3s'), // New tab
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
                        // 1. All Songs Tab (MediaStore)
                        _buildSongList(
                          list: _songs,
                          isRecordingList: false,
                          isDownloadedMp3List: false,
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
                        // 2. Downloaded MP3s Tab (Music folder)
                        _buildSongList(
                          list: _downloadedMp3s,
                          isRecordingList: false,
                          isDownloadedMp3List: true,
                          emptyIcon: Icons.download,
                          emptyTitle: 'No Downloaded MP3s',
                          emptySubtitle:
                              'MP3s downloaded from Old MP3 browser will appear here',
                          onRefresh: _loadDownloadedMp3s,
                          screenWidth: screenWidth,
                          screenHeight: screenHeight,
                          cardMargin: cardMargin,
                          emptyIconSize: emptyIconSize,
                          emptyTitleSize: emptyTitleSize,
                          emptySubtitleSize: emptySubtitleSize,
                          buttonPadding: buttonPadding,
                          iconSize: iconSize,
                        ),
                        // 3. Recordings Tab
                        _buildSongList(
                          list: _recordings,
                          isRecordingList: true,
                          isDownloadedMp3List: false,
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

                  Container(
                    alignment: Alignment.center,
                    height:
                        60, // A guaranteed height (50px is standard, use 60px for safety)
                    child: BannerAdWidget(),
                  ),
                  if (_currentSong != null && !_isPlayerExpanded)
                    _buildMiniPlayer(),
                ],
              ),
      ),
    );
  }
}
