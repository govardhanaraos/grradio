import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Mp3DownloadScreen extends StatefulWidget {
  @override
  _Mp3DownloadScreenState createState() => _Mp3DownloadScreenState();
}

class _Mp3DownloadScreenState extends State<Mp3DownloadScreen> {
  String? _selectedLanguage;
  String? _selectedFileType;
  final TextEditingController _searchController = TextEditingController();

  final List<String> _languages = ['Telugu', 'Hindi'];
  final List<String> _fileTypes = ['Albums', 'Songs', 'Artists', 'Playlists'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _searchMp3() {
    if (_selectedLanguage == null || _selectedFileType == null) {
      _showSnackbar('Please select both language and file type', Colors.red);
      return;
    }

    if (_searchController.text.isEmpty) {
      _showSnackbar('Please enter search text', Colors.red);
      return;
    }

    // TODO: Implement actual MP3 search functionality
    _showSnackbar(
      'Searching for $_selectedFileType in $_selectedLanguage: ${_searchController.text}',
      Colors.blue,
    );

    // Here you would typically make an API call to search for MP3 files
    print(
      'Searching MP3 - Language: $_selectedLanguage, Type: $_selectedFileType, Query: ${_searchController.text}',
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
                      labelText: 'Search Meaning',
                      hintText: 'Enter song name, artist, or keywords...',
                      border: InputBorder.none,
                      icon: Icon(CupertinoIcons.search, color: Colors.blueGrey),
                    ),
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),

              SizedBox(height: 30),

              // Search Button
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
                        '4. Click Search to find MP3 files',
                        style: TextStyle(color: Colors.blueGrey.shade700),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
