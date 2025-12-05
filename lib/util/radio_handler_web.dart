import 'dart:async';
import 'dart:js_interop';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:grradio/radiostation.dart';
import 'package:js/js.dart' as js; // alias to avoid conflict
import 'package:web/web.dart' as web;

import 'radio_handler_base.dart';

@js.JS('Hls')
class Hls {
  external factory Hls();
  external void loadSource(String url);
  external void attachMedia(web.HTMLVideoElement video);

  @js.JS('isSupported')
  external static bool isSupported();
}

/// Extension to convert JS Promise from play() into Dart Future
extension PlayFuture on web.HTMLMediaElement {
  Future<void> playFuture() => play().toDart;
}

class RadioHandlerImpl implements RadioHandlerBase {
  web.HTMLVideoElement? _video;
  Hls? _hls;
  bool _isRecording = false;
  final List<RadioStation> _radioStations;

  final _currentStationController = StreamController<RadioStation?>.broadcast();
  Stream<RadioStation?> get currentStationStream =>
      _currentStationController.stream;

  RadioStation? _currentStation;

  RadioHandlerImpl({required List<RadioStation> stations})
    : _radioStations = stations;

  // Expose mediaItem so UI can listen for updates
  final ValueNotifier<MediaItem?> mediaItem = ValueNotifier<MediaItem?>(null);
  final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);

  @override
  Future<void> playStation(RadioStation station) async {
    final url = station.streamUrl?.trim() ?? '';
    if (url.isEmpty) {
      print("❌ No stream URL for station: ${station.name}");
      return;
    }

    try {
      _video?.pause();
      _video = web.HTMLVideoElement()
        ..autoplay = true
        ..controls = false
        ..style.display = 'none';

      // ✅ Safari has native HLS support
      if (_video!.canPlayType('application/vnd.apple.mpegurl').isNotEmpty) {
        _video!.src = url;
      } else if (Hls.isSupported()) {
        // ✅ Chrome/Firefox → use hls.js
        _hls = Hls();
        _hls!.loadSource(url);
        _hls!.attachMedia(_video!);
      } else {
        print("❌ HLS not supported in this browser");
        return;
      }

      // Then in your handler:
      await _video!.playFuture();
      isPlaying.value = true;
      _currentStation = station;
      _currentStationController.add(station);

      mediaItem.value = MediaItem(
        id: station.id,
        title: station.name,
        artUri: Uri.tryParse(station.logoUrl ?? ''),
        genre: station.genre,
        extras: {'language': station.language, 'page': station.page},
      );

      print("✅ Playback started for ${station.name}");
    } catch (e) {
      print("❌ Playback error for ${station.name}: $e");
    }
  }

  @override
  Future<void> toggleRecord(dynamic mediaItem) async {
    print("Recording not supported on web");
  }

  @override
  bool get isRecording => false;

  @override
  Future<void> stop() async {
    _video?.pause();
    isPlaying.value = false;
    _currentStation = null;
    _currentStationController.add(null);
    _video = null;
    mediaItem.value = null;
  }

  Future<void> pause() async {
    _video?.pause();
    isPlaying.value = false;
  }

  Future<void> resume() async {
    await _video?.playFuture();
    isPlaying.value = true;
  }
}
