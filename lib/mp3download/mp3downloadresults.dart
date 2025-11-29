import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:grradio/ads/banner_ad_widget.dart';
import 'package:grradio/handler/mp3playerhandler.dart';
import 'package:grradio/main.dart';
import 'package:grradio/mp3download/albumdetailsscreen.dart';
import 'package:grradio/mp3download/mp3_constants.dart';
import 'package:grradio/responsebutton.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class Mp3DownloadResultsScreen extends StatefulWidget {
  final String searchQuery;
  final String language;
  final String fileType;

  const Mp3DownloadResultsScreen({
    Key? key,
    required this.searchQuery,
    required this.language,
    required this.fileType,
  }) : super(key: key);

  @override
  _Mp3DownloadResultsScreenState createState() =>
      _Mp3DownloadResultsScreenState();
}

class _Mp3DownloadResultsScreenState extends State<Mp3DownloadResultsScreen> {
  List<Map<String, dynamic>> _directories = [];
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // 💡 NEW: Add toggle states for sections
  bool _showDirectories = true;
  bool _showFiles = true;

  // 💡 NEW: Track expanded file and its details
  String? _expandedFileId;
  Map<String, dynamic>? _fileDetails;
  bool _loadingFileDetails = false;

  // 💡 NEW: Track download progress
  Map<String, double> _downloadProgress = {};
  Map<String, bool> _isDownloading = {};

  @override
  void initState() {
    super.initState();
    _fetchSearchResults();
  }

  Future<void> _fetchSearchResults() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
      String searchUrl = (widget.language == 'Telugu')
          ? Mp3Constants.teluguMP3Url
          : Mp3Constants.hindiMP3Url;
      final encodedQuery = Uri.encodeComponent(widget.searchQuery);
      final url = '$searchUrl/search.php?q=$encodedQuery';

      print('Fetching from: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        print('API Response: $jsonResponse');

        setState(() {
          //_directories = jsonResponse['directories'] ?? [];
          //_files = jsonResponse['files'] ?? [];
          var filesFromApi = jsonResponse['files'] as List<dynamic>;

          // Convert the List<dynamic> to List<Map<String, dynamic>>
          _files = filesFromApi
              .map((item) => item as Map<String, dynamic>)
              .toList();

          // Do the same for directories if necessary
          var directoriesFromApi = jsonResponse['directories'] as List<dynamic>;
          _directories = directoriesFromApi
              .map((item) => item as Map<String, dynamic>)
              .toList();
          _isLoading = false;
        });
      } else {
        throw Exception(
          'Failed to load search results. Status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error fetching results: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  // 💡 BETTER: Using HTML parser package
  Future<void> _fetchFileDetails(String fileId) async {
    if (_expandedFileId == fileId && _fileDetails != null) {
      setState(() {
        _expandedFileId = null;
        _fileDetails = null;
      });
      return;
    }

    setState(() {
      _loadingFileDetails = true;
      _expandedFileId = fileId;
    });

    try {
      String searchUrl = (widget.language == 'Telugu')
          ? Mp3Constants.teluguMP3Url
          : Mp3Constants.hindiMP3Url;
      final url = '$searchUrl/?fid=$fileId';
      print('Fetching file details from: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final document = html.parse(response.body);

        // Parse album name from breadcrumb
        String albumName = 'Unknown Album';
        final breadcrumbLinks = document.querySelectorAll('.bg a');
        if (breadcrumbLinks.length >= 3) {
          albumName = breadcrumbLinks[2].text?.trim() ?? 'Unknown Album';
        }

        // Parse download options
        final List<Map<String, String>> downloadLinks = [];
        final downloadOptionsDiv = document.querySelector('.download-options');

        if (downloadOptionsDiv != null) {
          final downloadAnchors = downloadOptionsDiv.querySelectorAll('a');
          for (final anchor in downloadAnchors) {
            final href = anchor.attributes['href'] ?? '';
            final text = anchor.text?.trim() ?? '';

            if (href.isNotEmpty && text.isNotEmpty) {
              downloadLinks.add({
                'text': text,
                'url': href.startsWith('http') ? href : '$searchUrl/$href',
              });
            }
          }
        }

        // Parse additional info
        String additionalInfo = '';
        final infoDiv = document.querySelector('.info');
        if (infoDiv != null) {
          additionalInfo = infoDiv.text?.trim() ?? '';
        }

        setState(() {
          _fileDetails = {
            'albumName': albumName,
            'downloadOptions': downloadLinks,
            'additionalInfo': additionalInfo,
          };
          _loadingFileDetails = false;
        });

        print('Parsed album name: $albumName');
        print('Parsed download options: $downloadLinks');
        print('Additional info: $additionalInfo');
      } else {
        throw Exception(
          'Failed to load file details. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error fetching file details: $e');
      setState(() {
        _fileDetails = {
          'albumName': 'Error loading details',
          'downloadOptions': [],
          'additionalInfo': '',
        };
        _loadingFileDetails = false;
      });
      _showSnackbar('Failed to load file details', Colors.red);
    }
  }

  Future<void> _downloadMp3NoPermission(String url, String mp3Name) async {
    print('⬇️ Starting download without permissions: $mp3Name');

    setState(() {
      _isLoading = true;
    });

    try {
      _showSnackbar('Downloading $mp3Name...', Colors.blue);

      // Use app's documents directory (no permissions needed)
      final directory = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${directory.path}/Music');

      // Create Music directory if it doesn't exist
      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      print('📁 Music directory: ${musicDir.path}');

      // Clean up filename
      String fileName = mp3Name;
      if (!fileName.toLowerCase().endsWith('.mp3')) {
        fileName += '.mp3';
      }
      fileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

      // Create file path
      final filePath = '${musicDir.path}/$fileName';
      final file = File(filePath);

      // Check if file already exists
      if (await file.exists()) {
        _showSnackbar('File already exists: $fileName', Colors.orange);
        return;
      }

      // Download the file
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);

        print('✅ Download completed: $filePath');
        print('📊 File size: ${file.lengthSync()} bytes');

        _showSnackbar('Downloaded: $fileName to Music folder', Colors.green);
      } else {
        print('❌ Download failed with status: ${response.statusCode}');
        _showSnackbar('Failed to download file', Colors.red);
      }
    } catch (e) {
      print('❌ Download error: $e');
      _showSnackbar('Download error: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ... rest of the methods remain exactly the same (all the download methods and UI builders)
  // Download methods (similar to your existing implementation)
  Future<void> _downloadFile(String url, String fileName) async {
    if (url.isEmpty) {
      _showSnackbar('Download URL is not available for: $fileName', Colors.red);
      return;
    }

    final downloadKey = '${url.hashCode}-$fileName';

    if (_isDownloading[downloadKey] == true) {
      _showSnackbar('Download already in progress: $fileName', Colors.blue);
      return;
    }

    try {
      setState(() {
        _isDownloading[downloadKey] = true;
        _downloadProgress[downloadKey] = 0.0;
      });

      final PermissionStatus status = await Permission.storage.request();
      if (!status.isGranted) {
        _showSnackbar(
          'Download cancelled: Storage permission required',
          Colors.orange,
        );
        return;
      }

      final Directory? downloadsDir = await _getDownloadDirectory();
      if (downloadsDir == null) {
        throw Exception('Could not access storage directory');
      }

      final downloadsFolder = Directory(
        '${downloadsDir.path}/GR Radio Downloads',
      );
      if (!await downloadsFolder.exists()) {
        await downloadsFolder.create(recursive: true);
      }

      String cleanFileName = _cleanFileName(fileName);
      if (!cleanFileName.toLowerCase().endsWith('.mp3')) {
        cleanFileName += '.mp3';
      }

      final filePath = '${downloadsFolder.path}/$cleanFileName';
      final file = File(filePath);

      if (await file.exists()) {
        final shouldOverwrite = await _showOverwriteDialog(cleanFileName);
        if (!shouldOverwrite) {
          _showSnackbar('Download cancelled: $cleanFileName', Colors.orange);
          return;
        }
      }

      final dio = Dio();
      _showSnackbar('Starting download: $cleanFileName', Colors.blue);

      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total) * 100;
            setState(() {
              _downloadProgress[downloadKey] = progress;
            });
          }
        },
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Accept': '*/*',
            'Connection': 'keep-alive',
          },
          receiveTimeout: Duration(minutes: 5),
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

      if (await file.exists()) {
        final fileSize = await file.length();
        final fileSizeFormatted = _formatFileSize(fileSize);
        await _showDownloadSuccessDialog(
          cleanFileName,
          fileSizeFormatted,
          filePath,
        );
      } else {
        throw Exception('File download verification failed');
      }
    } catch (e) {
      print('Download error: $e');
      _showSnackbar('Download failed: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isDownloading[downloadKey] = false;
        _downloadProgress.remove(downloadKey);
      });
    }
  }

  // 💡 ALTERNATIVE: Use Downloads directory specifically
  Future<Directory?> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      // For Android, try to get the Downloads directory
      try {
        final directory = await getDownloadsDirectory();
        if (directory != null) {
          return directory;
        }
      } catch (e) {
        print('Error getting downloads directory: $e');
      }

      // Fallback to external storage
      try {
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          return Directory('${directory.path}/Music');
        }
      } catch (e) {
        print('Error getting external storage: $e');
      }
    } else if (Platform.isIOS) {
      // For iOS, use documents directory
      return await getApplicationDocumentsDirectory();
    }

    // Final fallback
    return await getApplicationDocumentsDirectory();
  }

  // 💡 NEW: Improved permission checking method
  Future<bool> _checkAndRequestStoragePermission() async {
    if (Platform.isAndroid) {
      // For Android 13 (API 33) and above, we need different permissions
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }

      // Show permission dialog first
      final shouldProceed = await _showPermissionDialog();
      if (!shouldProceed) {
        return false;
      }

      // Request manage external storage permission for Android 10+
      final status = await Permission.manageExternalStorage.request();

      if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        final shouldOpenSettings = await _showPermissionSettingsDialog();
        if (shouldOpenSettings) {
          await openAppSettings();
        }
        return false;
      } else {
        // Try with just storage permission for older Android versions
        final storageStatus = await Permission.storage.request();
        return storageStatus.isGranted;
      }
    } else if (Platform.isIOS) {
      // For iOS, use photos permission or just check if we can write to documents
      final status = await Permission.storage.request();
      return status.isGranted;
    }

    return true;
  }

  // 💡 UPDATED: Permission dialog to mention Android 10+ requirements
  Future<bool> _showPermissionDialog() async {
    String message =
        'GR Radio needs storage permission to download and save MP3 files to your device. '
        'Your files will be saved in the "GR Radio Downloads" folder.';

    if (Platform.isAndroid) {
      message +=
          '\n\nOn Android 10 and above, this requires "Manage External Storage" permission to save to Downloads folder.';
    }

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Storage Permission Required'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Allow'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // 💡 NEW: Permission settings dialog for permanently denied permissions
  Future<bool> _showPermissionSettingsDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('Permission Required'),
              content: Text(
                'Storage permission is permanently denied. '
                'Please enable it in app settings to download files.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Open Settings'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // 💡 NEW: Download success dialog
  Future<void> _showDownloadSuccessDialog(
    String fileName,
    String fileSize,
    String filePath,
  ) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('Download Complete'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File: $fileName'),
              SizedBox(height: 4),
              Text('Size: $fileSize'),
              SizedBox(height: 8),
              Text(
                'File saved to:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                filePath,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // 💡 NEW: Clean filename for safe storage
  String _cleanFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // 💡 NEW: Format file size for display
  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  // 💡 NEW: Show overwrite confirmation dialog
  Future<bool> _showOverwriteDialog(String fileName) async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('File Exists'),
              content: Text(
                '"$fileName" already exists. Do you want to overwrite it?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Overwrite'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // 💡 NEW: Share downloaded file (optional feature)
  Future<void> _shareFile(String filePath, String fileName) async {
    // You can implement sharing functionality here
    // using the share_plus package
    print('File ready for sharing: $filePath');
  }

  // 💡 UPDATED: Build download button with progress
  Widget _buildDownloadButton({
    required String url,
    required String fileName,
    required String buttonText,
  }) {
    final downloadKey = '${url.hashCode}-$fileName';
    final isDownloading = _isDownloading[downloadKey] == true;
    final progress = _downloadProgress[downloadKey] ?? 0.0;

    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: isDownloading
                ? null
                : () => _downloadMp3NoPermission(url, fileName),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDownloading
                  ? Colors.grey.shade300
                  : Colors.green.shade50,
              foregroundColor: isDownloading
                  ? Colors.grey
                  : Colors.green.shade800,
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              minimumSize: Size(double.infinity, 40),
            ),
            icon: isDownloading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                    ),
                  )
                : Icon(CupertinoIcons.arrow_down_circle, size: 16),
            label: Text(
              isDownloading ? 'Downloading...' : buttonText,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          // Progress indicator
          if (isDownloading && progress > 0) ...[
            SizedBox(height: 4),
            LinearProgressIndicator(
              value: progress / 100,
              backgroundColor: Colors.green.shade100,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
            SizedBox(height: 2),
            Text(
              '${progress.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 10, color: Colors.green.shade700),
            ),
          ],
        ],
      ),
    );
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 3),
      ),
    );
  }

  // 💡 NEW: Build expandable section header
  Widget _buildSectionHeader({
    required String title,
    required int itemCount,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 2,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blueGrey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isExpanded ? CupertinoIcons.folder_open : CupertinoIcons.folder,
            color: Colors.blueGrey,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey.shade800,
          ),
        ),
        subtitle: Text(
          '$itemCount items',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: Icon(
          isExpanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
          color: Colors.blueGrey,
        ),
        onTap: onToggle,
      ),
    );
  }

  Widget _buildDirectoryItem(Map<String, dynamic> directory) {
    String searchUrl = (widget.language == 'Telugu')
        ? Mp3Constants.teluguMP3Url
        : Mp3Constants.hindiMP3Url;
    return Card(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 24),
      elevation: 2,
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
        leading: Container(
          width: RButton.getActionButtonSize() * 1.5,
          height: RButton.getActionButtonSize() * 1.5,
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Image.network(
              "$searchUrl/Data/thumbs/${directory['id']}.webp",
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
                    CupertinoIcons.folder_fill,
                    color: Colors.blueGrey,
                    size: RButton.getListIconSize(),
                  ),
                );
              },
            ),
          ),
        ),
        title: Text(
          directory['name'] ?? 'Unknown',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey.shade800,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            if (directory['year'] != null)
              Row(
                children: [
                  Icon(CupertinoIcons.calendar, size: 14, color: Colors.grey),
                  SizedBox(width: 4),
                  Text(
                    'Year: ${directory['year']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            if (directory['music'] != null && directory['music'].isNotEmpty)
              Row(
                children: [
                  Icon(CupertinoIcons.music_note, size: 14, color: Colors.grey),
                  SizedBox(width: 4),
                  Expanded(
                    // ADDED Expanded
                    child: Text(
                      'Music: ${directory['music'].join(', ')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis, // ADDED Ellipsis
                    ),
                  ),
                ],
              ),
            if (directory['artists'] != null && directory['artists'].isNotEmpty)
              Row(
                children: [
                  Icon(CupertinoIcons.person_2, size: 14, color: Colors.grey),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Artists: ${directory['artists'].join(', ')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(CupertinoIcons.arrow_down_circle, color: Colors.blueGrey),
          onPressed: () => _downloadItem(directory),
          tooltip: 'Download',
        ),
        onTap: () {
          // Navigate to album details screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AlbumDetailsScreen(
                albumId: directory['id'],
                albumName: directory['name'] ?? 'Unknown Album',
                targetUrl: searchUrl,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFileItem(Map<String, dynamic> file, int index) {
    final isExpanded = _expandedFileId == file['id'];
    final isLoadingDetails =
        _loadingFileDetails && _expandedFileId == file['id'];

    return Card(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 24),
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.all(16),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                CupertinoIcons.music_note,
                color: Colors.green,
                size: 20,
              ),
            ),
            title: Text(
              file['name'] ?? 'Unknown File',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: file['size'] != null
                ? Text(
                    'Size: ${file['size']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 💡 NEW: Play Button
                IconButton(
                  icon: const Icon(Icons.play_circle_fill, color: Colors.green),
                  onPressed: () {
                    // 🛑 You must ensure the radio stops when MP3 starts
                    // globalRadioAudioHandler.stop();
                    final List<SongData> validSongs = _files
                        .where(
                          (song) => song['url'] != null,
                        ) // Filter out null URLs
                        .toList();
                    // Pass the entire file list and the index
                    globalMp3QueueService.startQueue(_files, index);
                  },
                ),
                Icon(
                  isExpanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  color: Colors.green,
                ),
              ],
            ),
            onTap: () => _fetchFileDetails(file['id']),
          ),

          // 💡 NEW: Expanded section with file details
          if (isExpanded) ...[
            Divider(height: 1),
            if (isLoadingDetails)
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Loading details...',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              )
            else if (_fileDetails != null)
              _buildFileDetailsSection(file),
          ],
        ],
      ),
    );
  }

  // 💡 UPDATED: Build file details section with additional info
  Widget _buildFileDetailsSection(Map<String, dynamic> file) {
    final albumName = _fileDetails!['albumName'] ?? 'Unknown Album';
    final downloadOptions = List<Map<String, String>>.from(
      _fileDetails!['downloadOptions'] ?? [],
    );
    final additionalInfo = _fileDetails!['additionalInfo'] ?? '';
    final fileName = file['name'] ?? 'Unknown File';

    return Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Album Name
          Row(
            children: [
              Icon(
                CupertinoIcons.music_albums,
                size: 16,
                color: Colors.blueGrey,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Album: $albumName',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey.shade800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),

          // Additional Info (if available)
          if (additionalInfo.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Text(
                additionalInfo,
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700),
              ),
            ),
            SizedBox(height: 12),
          ],

          // Download Options
          Text(
            'Download Options:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.blueGrey.shade800,
            ),
          ),
          SizedBox(height: 8),

          if (downloadOptions.isEmpty)
            Text(
              'No download options available',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            ...downloadOptions.map((option) {
              final text = option['text'] ?? 'Download';
              final url = option['url'] ?? '';

              return _buildDownloadButton(
                url: url,
                fileName: '$fileName - $text',
                buttonText: text,
              );
            }).toList(),
        ],
      ),
    );
  }

  void _downloadItem(Map<String, dynamic> item) {
    _showSnackbar(
      'Download feature coming soon for: ${item['name']}',
      Colors.blue,
    );
  }

  Widget _buildResultsCount() {
    final totalResults = _directories.length + _files.length;
    return Padding(
      padding: EdgeInsets.all(16),
      child: Text(
        'Found $totalResults results for "${widget.searchQuery}"',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: Colors.blueGrey.shade700,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Searching for "${widget.searchQuery}"...',
            style: TextStyle(fontSize: 16, color: Colors.blueGrey),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle,
            size: 64,
            color: Colors.orange,
          ),
          SizedBox(height: 16),
          Text(
            'Search Failed',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          SizedBox(height: 8),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchSearchResults,
            child: Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.search, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No Results Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Try searching with different keywords',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Search Results',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueGrey.shade50, Colors.blueGrey.shade100],
          ),
        ),
        child: _isLoading
            ? _buildLoadingState()
            : _hasError
            ? _buildErrorState()
            : _directories.isEmpty && _files.isEmpty
            ? _buildEmptyState()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildResultsCount(),

                  // 💡 UPDATED: Albums/Folders section with toggle
                  if (_directories.isNotEmpty) ...[
                    _buildSectionHeader(
                      title: 'Albums/Folders',
                      itemCount: _directories.length,
                      isExpanded: _showDirectories,
                      onToggle: () {
                        setState(() {
                          _showDirectories = !_showDirectories;
                        });
                      },
                    ),
                    if (_showDirectories)
                      Expanded(
                        flex: 2,
                        child: ListView.builder(
                          itemCount: _directories.length,
                          itemBuilder: (context, index) {
                            return _buildDirectoryItem(
                              _directories[index] as Map<String, dynamic>,
                            );
                          },
                        ),
                      ),
                  ],

                  // 💡 UPDATED: Individual Files section with toggle
                  if (_files.isNotEmpty) ...[
                    _buildSectionHeader(
                      title: 'Individual Files',
                      itemCount: _files.length,
                      isExpanded: _showFiles,
                      onToggle: () {
                        setState(() {
                          _showFiles = !_showFiles;
                        });
                      },
                    ),
                    if (_showFiles)
                      Expanded(
                        flex: 1,
                        child: ListView.builder(
                          itemCount: _files.length,
                          itemBuilder: (context, index) {
                            return _buildFileItem(
                              _files[index] as Map<String, dynamic>,
                              index,
                            );
                          },
                        ),
                      ),
                  ],
                  Container(
                    alignment: Alignment.center,
                    height: 60, // Guaranteed space for the ad
                    child: const BannerAdWidget(),
                  ),
                  // 💡 NEW: Add some spacing at the bottom
                  if (_directories.isEmpty || _files.isEmpty)
                    SizedBox(height: 16),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchSearchResults,
        backgroundColor: Colors.blueGrey,
        child: Icon(CupertinoIcons.refresh, color: Colors.white),
        tooltip: 'Refresh Results',
      ),
    );
  }
}
