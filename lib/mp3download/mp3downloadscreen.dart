import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:grradio/ads/ad_helper.dart';
import 'package:grradio/ads/banner_ad_widget.dart';
import 'package:grradio/mp3download/mp3_constants.dart';
import 'package:grradio/mp3download/mp3downloadresults.dart';
import 'package:grradio/mp3download/oldmp3browserscreen.dart';

class Mp3DownloadScreen extends StatefulWidget {
  @override
  _Mp3DownloadScreenState createState() => _Mp3DownloadScreenState();
}

class _Mp3DownloadScreenState extends State<Mp3DownloadScreen> {
  String? _selectedLanguage;
  String? _selectedFileType;
  final TextEditingController _searchController = TextEditingController();

  // Use constants from the imported file
  final List<String> _languages = Mp3Constants.languages;
  final List<String> _fileTypes = Mp3Constants.fileTypes;

  final String _initialUrl = Mp3Constants.oldMp3InitialUrl;
  final String _teluguMP3Url = Mp3Constants.teluguMP3Url;
  final String _hindiMP3Url = Mp3Constants.hindiMP3Url;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 💡 UPDATED: Use the static helper to load the ad
    AdHelper.loadInterstitialAd();
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _searchMp3() async {
    String mp3Url = _teluguMP3Url;
    if (_selectedLanguage == null || _selectedFileType == null) {
      _showSnackbar('Please select both language and file type', Colors.red);
      return;
    }

    if (_searchController.text.isEmpty) {
      _showSnackbar('Please enter search text', Colors.red);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Navigate to results screen with search parameters
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Mp3DownloadResultsScreen(
            searchQuery: _searchController.text,
            language: _selectedLanguage!,
            fileType: _selectedFileType!,
          ),
        ),
      );
    } catch (e) {
      _showSnackbar('Error starting search: $e', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToOldMp3() async {
    setState(() {
      _isLoading = true;
    });

    // 💡 UPDATED: Show interstitial ad via helper before navigation
    // In mp3downloadscreen.dart, inside the function that handles navigation
    AdHelper.showInterstitialAd(
      onAdClosed: () {
        // 2. This code runs only AFTER the user closes the ad.
        try {
          // Determine the correct initial URL based on selected language
          String url;
          if (_selectedLanguage == 'Telugu') {
            url = _teluguMP3Url; // 'https://teluguwap.in' or similar
          } else if (_selectedLanguage == 'Hindi') {
            url = _hindiMP3Url; // 'https://hindiwap.in' or similar
          } else {
            url = _initialUrl; // Fallback URL
          }

          // 3. Navigate to the browser screen
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OldMp3Browser(initialUrl: url),
            ),
          );
        } catch (e) {
          // Handle any error during navigation/URL logic
          _showSnackbar('Error loading Old MP3: $e', Colors.red);
        } finally {
          // 4. Ensure loading state is turned off after the whole process
          setState(() {
            _isLoading = false;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'MP3 Download',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF388E3C), // Dark Green
                Color(0xFF66BB6A), // Light Green
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.blueGrey,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blueGrey.shade50, Colors.blueGrey.shade100],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Language Dropdown
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String>(
                    value: _selectedLanguage,
                    decoration: InputDecoration(
                      labelText: 'Select Language',
                      border: InputBorder.none,
                      icon: Icon(CupertinoIcons.globe, color: Colors.blueGrey),
                    ),
                    items: _languages.map((String language) {
                      return DropdownMenuItem<String>(
                        value: language,
                        child: Text(language, style: TextStyle(fontSize: 16)),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedLanguage = newValue;
                      });
                    },
                  ),
                ),
              ),

              SizedBox(height: 20),

              // File Type Dropdown
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: DropdownButtonFormField<String>(
                    value: _selectedFileType,
                    decoration: InputDecoration(
                      labelText: 'Select Type',
                      border: InputBorder.none,
                      icon: Icon(CupertinoIcons.folder, color: Colors.blueGrey),
                    ),
                    items: _fileTypes.map((String type) {
                      return DropdownMenuItem<String>(
                        value: type,
                        child: Text(type, style: TextStyle(fontSize: 16)),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedFileType = newValue;
                      });
                    },
                  ),
                ),
              ),

              SizedBox(height: 20),

              // Search Text Field
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextFormField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search Songs/Albums',
                      hintText: 'Enter movie name, song, or artist...',
                      border: InputBorder.none,
                      icon: Icon(CupertinoIcons.search, color: Colors.blueGrey),
                    ),
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              SizedBox(height: 30),

              // Search Button
              _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        ElevatedButton(
                          onPressed: _searchMp3,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.search, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'SEARCH MP3',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 10),
                        // Old MP3 Button
                        ElevatedButton(
                          onPressed: _navigateToOldMp3,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            elevation: 6,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.music_note, size: 20),
                              SizedBox(width: 10),
                              Text(
                                'OLD MP3',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

              SizedBox(height: 20),

              // Info Card
              Card(
                elevation: 2,
                color: Colors.blueGrey.withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.info,
                            color: Colors.blueGrey,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'How to use:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. Select your preferred language\n'
                        '2. Choose the type of content\n'
                        '3. Enter search keywords\n'
                        '4. Click Search to find MP3 files\n'
                        '5. Use Old MP3 for traditional browsing',
                        style: TextStyle(color: Colors.blueGrey.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 30), // Add separation
              // 💡 NEW: Banner Ad at the bottom
              Container(
                alignment: Alignment.center,
                height: 60,
                child: const BannerAdWidget(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
