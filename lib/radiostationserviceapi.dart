// radio_station_service.dart
import 'dart:convert';

import 'package:http/http.dart' as http; // Use the http package

import 'radiostation.dart';

// IMPORTANT: Use your deployed Render URL here.
const String _baseUrl = 'https://radio-backend-nysq.onrender.com';
const String _apiEndpoint = '/stations';

class RadioStationServiceAPI {
  // No need for _db or _connect() anymore!

  // Fetch all radio stations from the deployed FastAPI API
  Future<List<RadioStation>> fetchRadioStations() async {
    final uri = Uri.parse('$_baseUrl$_apiEndpoint');
    print('Fetching stations from: $uri');

    try {
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        // Decode the JSON list received from FastAPI
        final List<dynamic> jsonList = json.decode(response.body);
        print('Loaded Stations jsonList: ${jsonList}');
        // Convert the list of JSON Maps to a List of RadioStation objects
        return jsonList
            .map((map) => RadioStation.fromMap(map as Map<String, dynamic>))
            .toList();
      } else {
        // Handle server-side errors (e.g., 404, 500)
        print('Server returned status code ${response.statusCode}');
        print('Response body: ${response.body}');
        return [];
      }
    } catch (e) {
      // Handle network errors (e.g., no internet connection)
      print('Network error fetching radio stations: $e');
      return [];
    }
  }

  // The close method is no longer needed since we are not maintaining a DB connection.
  void close() {
    // No action needed for HTTP client
  }
}
