import 'package:audio_service/audio_service.dart';

class RadioStation {
  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String? language; // Lowercase 'language' in Dart model
  final String? genre; // Field is for the descriptive genre
  final String? state; // Field is for the location/state
  final String? page; // Field is for the location/state

  const RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.language,
    this.genre,
    this.state,
    this.page,
  });

  // Factory constructor to create a RadioStation from a MongoDB document map
  factory RadioStation.fromMap(Map<String, dynamic> map) {
    // MongoDB documents use '_id', which might be an ObjectId.
    // We try to convert it to a string for the 'id' field.
    final idString = map['_id']?.toString() ?? map['id']?.toString() ?? '';

    // --- FIXES FOR FIELD MISMATCH ---
    // 1. JSON field for language is 'Language' (capital L), map it to lowercase 'language'.
    final languageFromMap =
        map['Language'] as String? ?? map['language'] as String?;

    // 2. The state information (e.g., UTTAR PRADESH) is currently in the 'genre' field in the JSON.
    // We will assign the JSON 'genre' value to the model's 'state' field for better filtering.
    final stateFromMap = map['genre'] as String?;
    final pageFromMap = map['page'] as String?;

    return RadioStation(
      id: idString,
      name: map['name'] as String,
      streamUrl: map['streamUrl'] as String,
      // Use null-aware operators to safely assign optional fields
      logoUrl: map['logoUrl'] as String?,
      language: languageFromMap,
      genre:
          map['genre']
              as String?, // Keeping the original genre field mapped, but the value is the state
      state: stateFromMap, // Assigning the state/location value here
      page: pageFromMap, // Assigning the state/location value here
    );
  }

  MediaItem toMediaItem() => MediaItem(
    id: id,
    title: name,
    artist: state ?? 'Radio Station', // Use state as the artist/subtitle
    artUri: logoUrl != null ? Uri.parse(logoUrl!) : null,
    extras: <String, dynamic>{
      'streamUrl': streamUrl,
      'language': language,
      'genre': genre,
      'state': state,
      'page': page,
    },
  );

  RadioStation copyWith({
    String? id,
    String? name,
    String? streamUrl,
    String? logoUrl,
    String? language,
    String? genre,
    String? state,
    String? page,
  }) {
    return RadioStation(
      id: id ?? this.id,
      name: name ?? this.name,
      streamUrl: streamUrl ?? this.streamUrl,
      logoUrl: logoUrl ?? this.logoUrl,
      language: language ?? this.language,
      genre: genre ?? this.genre,
      state: state ?? this.state,
      page: page ?? this.page,
    );
  }
}
