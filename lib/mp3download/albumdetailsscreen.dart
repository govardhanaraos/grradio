import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart'; // 💡 NEW: For MediaItem
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:grradio/ads/banner_ad_widget.dart';
import 'package:grradio/main.dart'; // 💡 NEW: To access globalMp3QueueService
import 'package:grradio/mp3download/mp3miniplayer.dart';
import 'package:html/dom.dart'
    as html_dom; // Fix: Use 'as' to prevent naming conflicts
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AlbumDetailsScreen extends StatefulWidget {
  final String albumId;
  final String albumName;
  final String targetUrl;

  const AlbumDetailsScreen({
    Key? key,
    required this.albumId,
    required this.albumName,
    required this.targetUrl,
  }) : super(key: key);

  @override
  _AlbumDetailsScreenState createState() => _AlbumDetailsScreenState();
}

class _AlbumDetailsScreenState extends State<AlbumDetailsScreen> {
  List<Map<String, dynamic>> _songs = [];
  Map<String, dynamic>? _albumInfo;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  bool _showMiniPlayer = false;
  String _currentSongTitle = '';

  String? _expandedFileId;
  Map<String, dynamic>? _fileDetails;
  bool _loadingFileDetails = false;

  // Download tracking
  Map<String, double> _downloadProgress = {};
  Map<String, bool> _isDownloading = {};

  int _currentPage = 1;
  int _totalPages = 1;
  List<int> _pageNumbers = [];

  @override
  void initState() {
    super.initState();
    _fetchAlbumDetails();

    globalMp3QueueService.mediaItem.listen((item) {
      if (item != null) {
        setState(() {
          _currentSongTitle = item.title;
        });
      }
    });
  }

  Future<void> _fetchAlbumDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final url = '${widget.targetUrl}/?did=${widget.albumId}';
      print('Fetching album details from: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        _parseAlbumDetails(response.body);
      } else {
        throw Exception(
          'Failed to load album details. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error fetching album details: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  void _parseAlbumDetails(String htmlContent) {
    try {
      final document = html_parser.parse(htmlContent);

      // Parse album info from folder-info section
      final albumInfo = (widget.targetUrl.toLowerCase().contains('hindi'))
          ? _parseAlbumInfoHindi(document)
          : _parseAlbumInfo(document);

      // Parse songs from bg divs
      final songs = (widget.targetUrl.toLowerCase().contains('hindi'))
          ? _parseSongsHindi(document)
          : _parseSongs(document);

      _parsePagination(htmlContent);

      setState(() {
        _albumInfo = albumInfo;
        _songs = songs;
        _isLoading = false;
      });

      print('Parsed album info: $albumInfo');
      print('Parsed ${songs.length} songs');
    } catch (e) {
      print('Error parsing album details: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to parse album details: $e';
      });
    }
  }

  Map<String, dynamic> _parseAlbumInfo(dynamic document) {
    final Map<String, dynamic> info = {
      'coverUrl': '',
      'title': '',
      'year': '',
      'actors': [],
      'director': '',
      'music': '',
    };

    try {
      // Parse cover image
      final coverImg = document.querySelector('.folder-info img');
      if (coverImg != null) {
        String src = coverImg.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.startsWith('http')) {
          src = '${widget.targetUrl}/$src';
        }
        info['coverUrl'] = src;
      }

      // Parse album title and info - FIXED: Use simpler selector
      final infoTd = document.querySelector('.folder-info table td');
      if (infoTd != null) {
        // Find the second TD (info column) by checking if it's not the first one with image
        final allTds = document.querySelectorAll('.folder-info table td');
        var infoTdElement;

        if (allTds.length > 1) {
          infoTdElement = allTds[1]; // Second TD contains the info
        }

        if (infoTdElement != null) {
          // Parse title
          final titleElement = infoTdElement.querySelector('h3');
          if (titleElement != null) {
            info['title'] = titleElement.text?.trim() ?? widget.albumName;
          }

          // Parse year - look for year links in paragraphs
          final paragraphs = infoTdElement.querySelectorAll('p');
          for (final p in paragraphs) {
            final text = p.text?.trim() ?? '';
            if (text.contains('📅') || text.contains('Year')) {
              final yearLinks = p.querySelectorAll('a[href*="year="]');
              if (yearLinks.isNotEmpty) {
                info['year'] = yearLinks.first.text?.trim() ?? '';
                break;
              }
            }
          }

          // Parse actors - look in actor paragraphs
          for (final p in paragraphs) {
            final text = p.text?.trim() ?? '';
            if (text.contains('👫🏻') || text.contains('Actor')) {
              final actorLinks = p.querySelectorAll('a[href*="actor"]');
              info['actors'] = actorLinks
                  .map<String>(
                    (html_dom.Element element) => element.text?.trim() ?? '',
                  )
                  .where((String name) => name.isNotEmpty)
                  .toList();
              print('info[\'actors\'] : ${info['actors']}');
              break;
            }
          }

          // Parse director - look in director paragraphs
          for (final p in paragraphs) {
            final text = p.text?.trim() ?? '';
            print('director: text: $text');
            if (text.contains('🎥') || text.contains('Director')) {
              print('inside if condition1');
              final directorLinks = p.querySelectorAll('a[href*="director="]');
              print(' directorLinks: $directorLinks');
              if (directorLinks.isNotEmpty) {
                info['director'] = directorLinks.first.text?.trim() ?? '';
              }
              break;
            }
          }

          // Parse music - look in music paragraphs
          for (final p in paragraphs) {
            final text = p.text?.trim() ?? '';
            if (text.contains('🎹') || text.contains('Music')) {
              final musicLinks = p.querySelectorAll('a[href*="music="]');
              if (musicLinks.isNotEmpty) {
                info['music'] = musicLinks.first.text?.trim() ?? '';
              }
              break;
            }
          }
        }
      }
    } catch (e) {
      print('Error parsing album info: $e');
    }
    print('album info: $info');
    return info;
  }

  List<Map<String, dynamic>> _parseSongs(dynamic document) {
    final List<Map<String, dynamic>> songs = [];

    try {
      final songDivs = document.querySelectorAll('.container .bg');

      for (final div in songDivs) {
        // Skip the ZIP download section
        bool hasZip = false;
        final allAnchors = div.querySelectorAll('a');
        for (final anchor in allAnchors) {
          final href = anchor.attributes['href'] ?? '';
          if (href.contains('zip') || href.contains('zip.php')) {
            hasZip = true;
            break;
          }
        }
        if (hasZip) continue;

        final Map<String, dynamic> song = {
          'id': '',
          'title': '',
          'size': '',
          'url': '',
          'singers': [],
        };

        // Get all anchors in this .bg div
        final anchors = div.querySelectorAll('a[href*="fid="]');

        if (anchors.length > 0) {
          for (final anchor in anchors) {
            final href = anchor.attributes['href'] ?? '';
            if (href.contains('fid=')) {
              if (anchor != null) {
                final anchorText = anchor.text?.trim() ?? '';
                final anchorHref = anchor.attributes['href'] ?? '';

                // Extract ID from href
                if (anchorHref.contains('fid=')) {
                  final id = anchorHref.split('fid=')[1].split('&').first;
                  song['id'] = id;
                  song['url'] = '${widget.targetUrl}/?fid=$id';
                }

                // Find the immediate next small tag after this anchor
                String sizeText = '';
                final allElements = div.querySelectorAll('*');
                bool foundTargetAnchor = false;

                for (final element in allElements) {
                  if (element == anchor) {
                    foundTargetAnchor = true;
                    continue;
                  }

                  if (foundTargetAnchor && element.localName == 'small') {
                    sizeText = element.text?.trim() ?? '';
                    foundTargetAnchor = false;
                    break;
                  }
                }

                song['title'] = '$anchorText';
                song['size'] = '${sizeText.trim()}';
              }
            }
          }
        }

        // Parse singers - look for singers-info class
        final singersInfo = div.querySelector('.singers-info');
        if (singersInfo != null) {
          final singerAnchors = singersInfo.querySelectorAll(
            'a[href*="singer="]',
          );
          song['singers'] = singerAnchors
              .map<String>(
                (html_dom.Element element) => element.text?.trim() ?? '',
              )
              .where((String name) => name.isNotEmpty)
              .toList();
        }
        if (song['title'].isNotEmpty && song['id'].isNotEmpty) {
          songs.add(song);
        }
      }
    } catch (e) {
      print('Error parsing songs: $e');
    }

    return songs;
  }

  void _parsePagination(String htmlContent) {
    try {
      final document = html_parser.parse(htmlContent);

      // Find pagination nav element
      final paginationNav = document.querySelector('.pagination-nav');

      if (paginationNav != null) {
        final pageButtons = paginationNav.querySelectorAll('a.pagination-btn');

        // Extract page numbers from buttons
        final List<int> pages = [];
        int currentPage = 1;

        for (final button in pageButtons) {
          final href = button.attributes['href'] ?? '';
          final text = button.text?.trim() ?? '';
          final isActive = button.classes.contains('active');

          // Parse page number from href
          if (href.contains('page=')) {
            final pageMatch = RegExp(r'page=(\d+)').firstMatch(href);
            if (pageMatch != null) {
              final pageNum = int.tryParse(pageMatch.group(1) ?? '1');
              if (pageNum != null) {
                pages.add(pageNum);
                if (isActive) {
                  currentPage = pageNum;
                }
              }
            }
          }

          // Also check for numeric text (like "1", "2", etc.)
          if (text.isNotEmpty && RegExp(r'^\d+$').hasMatch(text)) {
            final pageNum = int.tryParse(text);
            if (pageNum != null && !pages.contains(pageNum)) {
              pages.add(pageNum);
              if (isActive) {
                currentPage = pageNum;
              }
            }
          }
        }

        if (pages.isNotEmpty) {
          setState(() {
            _pageNumbers = pages..sort();
            _currentPage = currentPage;
            _totalPages = _pageNumbers.isNotEmpty ? _pageNumbers.last : 1;
          });
        }
      } else {
        // No pagination found, reset to single page
        setState(() {
          _currentPage = 1;
          _totalPages = 1;
          _pageNumbers = [1];
        });
      }
    } catch (e) {
      print('Error parsing pagination: $e');
      // Default to single page on error
      setState(() {
        _currentPage = 1;
        _totalPages = 1;
        _pageNumbers = [1];
      });
    }
  }

  Future<void> _navigateToPage(int page) async {
    if (page == _currentPage) return;

    try {
      setState(() {
        _isLoading = true;
      });

      final url = '${widget.targetUrl}/?did=${widget.albumId}&page=$page';
      print('Fetching page $page from: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        _parseAlbumDetails(response.body);
      } else {
        throw Exception(
          'Failed to load page $page. Status: ${response.statusCode}',
        );
      }
    } catch (e) {
      print('Error navigating to page $page: $e');
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to load page $page: $e';
      });
    }
  }

  Widget _buildPaginationNav() {
    if (_totalPages <= 1) return const SizedBox(); // Hide if only one page

    return Container(
      margin: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 4,
      ), // smaller margin
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ), // tighter padding
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8), // smaller radius
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 2,
            offset: Offset(0, 1),
          ), // lighter shadow
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_currentPage > 1)
            _buildPaginationButton(
              text: '‹',
              page: _currentPage - 1,
              isActive: false,
            ),
          ..._pageNumbers.map(
            (page) => _buildPaginationButton(
              text: '$page',
              page: page,
              isActive: page == _currentPage,
            ),
          ),
          if (_currentPage < _totalPages)
            _buildPaginationButton(
              text: '›',
              page: _currentPage + 1,
              isActive: false,
            ),
        ],
      ),
    );
  }

  Widget _buildPaginationButton({
    required String text,
    required int page,
    required bool isActive,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton(
        onPressed: () => _navigateToPage(page),
        style: TextButton.styleFrom(
          backgroundColor: isActive
              ? Colors.blueGrey.shade100
              : Colors.transparent,
          foregroundColor: isActive
              ? Colors.blueGrey.shade800
              : Colors.blueGrey,
          minimumSize: const Size(32, 28), // smaller button size
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ), // tighter padding
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(
              color: isActive ? Colors.blueGrey : Colors.grey.shade300,
            ),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _parseAlbumInfoHindi(dynamic document) {
    final Map<String, dynamic> info = {
      'coverUrl': '',
      'title': '',
      'year': '',
      'actors': [],
      'director': '',
      'music': '',
    };

    try {
      final coverImg = document.querySelector('.album-cover-large img');
      if (coverImg != null) {
        String src = coverImg.attributes['src'] ?? '';
        if (src.isNotEmpty && !src.startsWith('http')) {
          src = '${widget.targetUrl}/$src';
        }
        info['coverUrl'] = src;
      }

      final infoTd = document.querySelector('.album-details');
      if (infoTd != null) {
        final allTds = document.querySelectorAll('.album-details');
        var infoTdElement;
        if (allTds.length > 0) {
          infoTdElement = allTds[0];
        }

        if (infoTdElement != null) {
          final titleElement = infoTdElement.querySelector('h1');
          if (titleElement != null) {
            info['title'] = titleElement.text?.trim() ?? widget.albumName;
          }
          final paragraphs = infoTdElement.querySelectorAll('.meta-info');
          for (final p in paragraphs) {
            final text = p.text?.trim() ?? '';
            if (text.contains('📅') || text.contains('Year')) {
              final yearLinks = p.querySelectorAll('a[href*="year="]');
              if (yearLinks.isNotEmpty) {
                info['year'] = yearLinks.first.text?.trim() ?? '';
                break;
              }
            }
          }

          for (final p in paragraphs) {
            final text = p.text?.trim() ?? '';
            if (text.contains('👫🏻') || text.contains('Actor')) {
              final actorLinks = p.querySelectorAll('a[href*="actor"]');
              info['actors'] = actorLinks
                  .map<String>(
                    (html_dom.Element element) => element.text?.trim() ?? '',
                  )
                  .where((String name) => name.isNotEmpty)
                  .toList();
              break;
            }
          }
          for (final p in paragraphs) {
            final text = p.text?.trim() ?? '';
            if (text.contains('🎥') || text.contains('Director')) {
              final directorLinks = p.querySelectorAll('a[href*="director="]');
              if (directorLinks.isNotEmpty) {
                info['director'] = directorLinks.first.text?.trim() ?? '';
              }
              break;
            }
          }
          for (final p in paragraphs) {
            final text = p.text?.trim() ?? '';
            if (text.contains('🎹') || text.contains('Music')) {
              final musicLinks = p.querySelectorAll('a[href*="music="]');
              if (musicLinks.isNotEmpty) {
                info['music'] = musicLinks.first.text?.trim() ?? '';
              }
              break;
            }
          }
        }
      }
    } catch (e) {
      print('Error parsing album info: $e');
    }
    return info;
  }

  List<Map<String, dynamic>> _parseSongsHindi(dynamic document) {
    final List<Map<String, dynamic>> songs = [];

    try {
      final songDiv = document.querySelector('.container .bg table');
      if (songDiv != null) {
        final songDivs = document.querySelectorAll('.container .bg table');
        for (final div in songDivs) {
          bool hasZip = false;
          final allAnchors = div.querySelectorAll('a');
          for (final anchor in allAnchors) {
            final href = anchor.attributes['href'] ?? '';
            if (href.contains('zip') || href.contains('zip.php')) {
              hasZip = true;
              break;
            }
          }
          if (hasZip) continue;

          final Map<String, dynamic> song = {
            'id': '',
            'title': '',
            'size': '',
            'url': '',
            'singers': [],
          };

          final anchors = div.querySelectorAll('a[href*="fid="]');

          if (anchors.length > 0) {
            for (final anchor in anchors) {
              final href = anchor.attributes['href'] ?? '';
              if (href.contains('fid=')) {
                if (anchor != null) {
                  final anchorText = anchor.text?.trim() ?? '';
                  final anchorHref = anchor.attributes['href'] ?? '';

                  if (anchorHref.contains('fid=')) {
                    final id = anchorHref.split('fid=')[1].split('&').first;
                    song['id'] = id;
                    song['url'] = '${widget.targetUrl}/?fid=$id';
                  }

                  song['title'] = '$anchorText';
                }
              }
            }
          }

          final singersInfo = div.querySelector('a[href*="singer="]');
          if (singersInfo != null) {
            final singerAnchors = div.querySelectorAll('a[href*="singer="]');
            song['singers'] = singerAnchors
                .map<String>(
                  (html_dom.Element element) => element.text?.trim() ?? '',
                )
                .where((String name) => name.isNotEmpty)
                .toList();
          }
          if (song['title'].isNotEmpty && song['id'].isNotEmpty) {
            songs.add(song);
          }
        }
      }
    } catch (e) {
      print('Error parsing songs: $e');
    }

    return songs;
  }

  Future<void> _downloadMp3NoPermission(String url, String mp3Name) async {
    print('⬇️ Starting download without permissions: $mp3Name');

    setState(() {
      _isLoading = true;
    });

    try {
      _showSnackbar('Downloading $mp3Name...', Colors.blue);

      final directory = await getApplicationDocumentsDirectory();
      final musicDir = Directory('${directory.path}/Music');

      if (!await musicDir.exists()) {
        await musicDir.create(recursive: true);
      }

      String fileName = mp3Name;
      if (!fileName.toLowerCase().endsWith('.mp3')) {
        fileName += '.mp3';
      }
      fileName = fileName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

      final filePath = '${musicDir.path}/$fileName';
      final file = File(filePath);

      if (await file.exists()) {
        _showSnackbar('File already exists: $fileName', Colors.orange);
        return;
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
        _showSnackbar('Downloaded: $fileName to Music folder', Colors.green);
      } else {
        _showSnackbar('Failed to download file', Colors.red);
      }
    } catch (e) {
      _showSnackbar('Download error: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 💡 NEW: Helper to extract best URL for streaming
  Future<String?> _extractBestStreamUrl(String fileId) async {
    try {
      final url = '${widget.targetUrl}/?fid=$fileId';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);
        final downloadOptionsDiv = document.querySelector('.download-options');

        if (downloadOptionsDiv != null) {
          final anchors = downloadOptionsDiv.querySelectorAll('a');
          String? bestUrl;
          String? mediumUrl;
          String? anyUrl;

          for (final anchor in anchors) {
            final href = anchor.attributes['href'] ?? '';
            final text = anchor.text?.trim() ?? '';
            if (href.isNotEmpty) {
              final fullUrl = href.startsWith('http')
                  ? href
                  : '${widget.targetUrl}/$href';

              anyUrl ??= fullUrl; // Fallback to first available

              if (text.contains('128') || text.contains('Medium')) {
                mediumUrl = fullUrl;
              }
              if (text.contains('320') || text.contains('High')) {
                bestUrl = fullUrl;
              }
            }
          }
          return bestUrl ?? mediumUrl ?? anyUrl;
        }
      }
    } catch (e) {
      print('Error extracting stream URL for $fileId: $e');
    }
    return null;
  }

  Future<void> _playAllSongs() async {
    if (_songs.isEmpty) return;

    if (globalMp3QueueService == null) {
      _showSnackbar(
        'Audio service is not ready. Try restarting the app.',
        Colors.red,
      );
      print('ERROR: globalMp3QueueService is null. Playback aborted.');
      return;
    }

    // Show loading indicator
    /*showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => Center(child: CircularProgressIndicator()),
    );*/

    try {
      // 1. Create MediaItems for all songs
      final List<MediaItem> mediaItems = [];

      for (final song in _songs) {
        final mediaItem = MediaItem(
          id: song['id'] as String,
          album: _albumInfo?['title'] ?? widget.albumName,
          title: song['title'] as String,
          artist:
              (song['singers'] as List<dynamic>?)?.join(', ') ??
              'Unknown Artist',
          duration: null,
          artUri:
              (_albumInfo?['coverUrl'] as String?) != null &&
                  (_albumInfo?['coverUrl'] as String).isNotEmpty
              ? Uri.parse(_albumInfo?['coverUrl'] as String)
              : null,
        );
        mediaItems.add(mediaItem);
      }

      // 2. Set the entire queue first
      await globalMp3QueueService.setQueue(mediaItems, widget.targetUrl);

      // 3. Load and play the first song
      if (mediaItems.isNotEmpty) {
        setState(() {
          _showMiniPlayer = true;
          _currentSongTitle = mediaItems.first.title;
        });
        await globalMp3QueueService.loadAndPlayFirstSong();
      }

      //Navigator.pop(context); // Dismiss loading
      _showSnackbar('Playing all songs...', Colors.green);
    } catch (e) {
      Navigator.pop(context); // Dismiss loading
      _showSnackbar('Error playing all: $e', Colors.red);
      print('Error in _playAllSongs: $e');
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds';
    } else {
      return '$minutes:$seconds';
    }
  }

  Future<Directory?> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      try {
        return await getDownloadsDirectory();
      } catch (e) {
        print('Error getting downloads directory: $e');
      }
      try {
        return await getExternalStorageDirectory();
      } catch (e) {
        print('Error getting external storage: $e');
      }
    } else if (Platform.isIOS) {
      return await getApplicationDocumentsDirectory();
    }
    return await getApplicationDocumentsDirectory();
  }

  String _cleanFileName(String fileName) {
    return fileName
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    final i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

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

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildDownloadButton({
    required String url,
    required String fileName,
    required String buttonText,
  }) {
    // ... [Same implementation as before]
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

  Widget _buildAlbumHeader() {
    if (_albumInfo == null) return SizedBox();

    return Card(
      margin: EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _albumInfo!['coverUrl'].isNotEmpty
                    ? Image.network(
                        _albumInfo!['coverUrl'],
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(child: CircularProgressIndicator());
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade200,
                            child: Icon(
                              CupertinoIcons.music_albums,
                              size: 40,
                              color: Colors.grey.shade400,
                            ),
                          );
                        },
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        child: Icon(
                          CupertinoIcons.music_albums,
                          size: 40,
                          color: Colors.grey.shade400,
                        ),
                      ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _albumInfo!['title'] ?? widget.albumName,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey.shade800,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 8),
                  if (_albumInfo!['year'].isNotEmpty)
                    _buildInfoRow('📅', 'Year: ${_albumInfo!['year']}'),
                  if (_albumInfo!['actors'].isNotEmpty)
                    _buildInfoRow(
                      '👫🏻',
                      'Actors: ${_albumInfo!['actors'].join(', ')}',
                    ),
                  if (_albumInfo!['director'].isNotEmpty)
                    _buildInfoRow('🎥', 'Director: ${_albumInfo!['director']}'),
                  if (_albumInfo!['music'].isNotEmpty)
                    _buildInfoRow('🎹', 'Music: ${_albumInfo!['music']}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String icon, String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: TextStyle(fontSize: 12)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongItem(Map<String, dynamic> song, int index) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(CupertinoIcons.music_note, color: Colors.blue, size: 20),
        ),
        title: Text(
          song['title'],
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (song['size'].isNotEmpty)
              Text(
                'Size: ${song['size']}',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            if (song['singers'].isNotEmpty)
              Text(
                'Singers: ${song['singers'].join(', ')}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(CupertinoIcons.arrow_down_circle, color: Colors.blue),
          onPressed: () => _downloadMp3NoPermission(song['url'], song['title']),
          tooltip: 'Download',
        ),
      ),
    );
  }

  Widget _buildFileItem(Map<String, dynamic> file) {
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
              file['title'] ?? 'Unknown File',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            subtitle: (widget.targetUrl.toLowerCase().contains('hindi'))
                ? null
                : ((file['size'] != null || file['size'] != '')
                      ? Text(
                          'Size: ${file['size']}',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        )
                      : null),
            trailing: Icon(
              isExpanded
                  ? CupertinoIcons.chevron_up
                  : CupertinoIcons.chevron_down,
              color: Colors.green,
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
                  'Album/Singer: $albumName',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey.shade800,
                  ),
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
      final url = '${widget.targetUrl}/?fid=$fileId';
      print('Fetching file details from: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final document = html_parser.parse(response.body);

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
                'url': href.startsWith('http')
                    ? href
                    : '${widget.targetUrl}/$href',
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

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading album details...',
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
            'Failed to load album',
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
            onPressed: _fetchAlbumDetails,
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
          Icon(CupertinoIcons.music_albums, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'No Songs Found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'This album appears to be empty',
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
          'Album Details',
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
            : Column(
                children: [
                  _buildAlbumHeader(),
                  SizedBox(height: 8),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Songs (${_songs.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey.shade800,
                          ),
                        ),
                        // 💡 NEW: Play All Button
                        if (_songs.isNotEmpty)
                          ElevatedButton.icon(
                            icon: Icon(Icons.play_arrow, size: 18),
                            label: Text('Play All'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueGrey,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              textStyle: TextStyle(fontSize: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                            onPressed: _playAllSongs,
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 8),
                  Expanded(
                    child: _songs.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            itemCount: _songs.length,
                            itemBuilder: (context, index) {
                              return _buildFileItem(_songs[index]);
                            },
                          ),
                  ),

                  _buildPaginationNav(),
                ],
              ),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BannerAdWidget(),
          if (_showMiniPlayer)
            StreamBuilder<bool>(
              stream: globalMp3QueueService.playbackState
                  .map((s) => s.playing)
                  .distinct(),
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? false;
                return MiniPlayer(
                  title: _currentSongTitle,
                  positionStream: globalMp3QueueService.player.positionStream,
                  durationStream: globalMp3QueueService.player.durationStream,
                  isPlaying: isPlaying,
                  onPause: () => globalMp3QueueService.pause(),
                  onPlay: () => globalMp3QueueService.play(),
                  onClose: () async {
                    await globalMp3QueueService.stop();
                    setState(() => _showMiniPlayer = false);
                  },
                );
              },
            ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _fetchAlbumDetails,
        backgroundColor: Colors.blueGrey,
        child: Icon(CupertinoIcons.refresh, color: Colors.white),
        tooltip: 'Refresh',
      ),
    );
  }
}
