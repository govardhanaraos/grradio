// radio_handler_base.dart
import 'package:audio_service/audio_service.dart';
import 'package:grradio/radiostation.dart';

abstract class RadioHandlerBase {
  Future<void> playStation(RadioStation station);
  Future<void> stop();
  Future<void> toggleRecord(MediaItem? mediaItem);
  bool get isRecording;
}
