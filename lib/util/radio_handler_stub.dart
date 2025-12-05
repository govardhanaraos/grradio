// radio_handler_stub.dart
import 'package:grradio/radiostation.dart';

import 'radio_handler_base.dart';

class RadioHandlerStub implements RadioHandlerBase {
  @override
  Future<void> playStation(RadioStation station) async {
    throw UnsupportedError("Platform not supported");
  }

  @override
  Future<void> stop() async {}

  @override
  // TODO: implement isRecording
  bool get isRecording => throw UnimplementedError();

  @override
  Future<void> toggleRecord(mediaItem) {
    // TODO: implement toggleRecord
    throw UnimplementedError();
  }
}
