import 'package:audio_service/audio_service.dart';

class RadioStation {
  final String id;
  final String name;
  final String streamUrl;
  final String? logoUrl;
  final String? language;
  final String? description;

  const RadioStation({
    required this.id,
    required this.name,
    required this.streamUrl,
    this.logoUrl,
    this.language,
    this.description,
  });

  // Factory constructor to create a RadioStation from a MongoDB document map
  factory RadioStation.fromMap(Map<String, dynamic> map) {
    // MongoDB documents use '_id', which might be an ObjectId.
    // We try to convert it to a string for the 'id' field.
    final idString = map['_id']?.toString() ?? map['id']?.toString() ?? '';

    return RadioStation(
      id: idString,
      name: map['name'] as String,
      streamUrl: map['streamUrl'] as String,
      // Use null-aware operators to safely assign optional fields
      logoUrl: map['logoUrl'] as String?,
      language: map['language'] as String?,
      description: map['description'] as String?,
    );
  }

  MediaItem toMediaItem() => MediaItem(
    id: id,
    title: name,
    artist: 'Internet Radio',
    genre: language,
    artUri: logoUrl != null ? Uri.parse(logoUrl!) : null,
    extras: {'description': description},
  );
}

// NOTE: The hardcoded 'radioStations' list is no longer here.
// You will load the stations dynamically using the RadioStationService.
