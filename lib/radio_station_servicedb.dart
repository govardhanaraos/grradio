import 'package:mongo_dart/mongo_dart.dart';

import 'radiostation.dart';

// ⚠️ IMPORTANT: Replace this with your actual MongoDB connection string.
// Example: 'mongodb://<user>:<password>@<host>:<port>/<dbname>?authSource=admin'
const String mongoConnectionString =
    'mongodb+srv://govardhanaraofmuser:mK18NY3DJ260hsrp@cluster0.mihjnbk.mongodb.net/GRRadio?retryWrites=true&w=majority&authSource=admin';
//'mongodb://govardhanaraofmuser:mK18NY3DJ260hsrp@atlas-sql-690d90acc3db4977165ba1c3-evtrqj.a.query.mongodb.net/GRRADIO?ssl=true&authSource=admin&appName=Cluster0';
const String collectionName = 'radio_stations'; // The name of your collection

class RadioStationServiceDB {
  late Db _db;

  // Initialize the database connection
  Future<void> _connect() async {
    // Prevents reconnecting if already connected
    print('Before connection check');
    //if (_db!= null && _db!.isConnected) return;
    print('After connection check');
    try {
      print('Before connection create ');
      _db = await Db.create(mongoConnectionString);
      print('after connection create ');
      await _db.open();
      print('Successfully connected to MongoDB.');
    } catch (e) {
      print('Error connecting to MongoDB: $e');
      // In a real application, you would handle this error gracefully (e.g., show a dialog)
      rethrow;
    }
  }

  // Fetch all radio stations from the MongoDB table/collection
  Future<List<RadioStation>> fetchRadioStations() async {
    await _connect();

    if (!_db.isConnected) {
      print('Database not connected. Cannot fetch stations.');
      return [];
    }

    try {
      final collection = _db.collection(collectionName);
      // Retrieve all documents from the collection
      final stationsList = await collection.find().toList();

      // Convert the list of MongoDB Maps to a List of RadioStation objects
      return stationsList.map((map) => RadioStation.fromMap(map)).toList();
    } catch (e) {
      print('Error fetching radio stations: $e');
      return [];
    }
  }

  // Close the database connection (call this when the app is closing or done fetching)
  void close() {
    if (_db.isConnected) {
      _db.close();
      print('MongoDB connection closed.');
    }
  }
}
