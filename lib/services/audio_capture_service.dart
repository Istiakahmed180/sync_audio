abstract class AudioCaptureService {
  Future<void> start();
  Future<void> stop();
  bool get isCapturing;
}

class PlaceholderAudioCaptureService implements AudioCaptureService {
  @override
  bool isCapturing = false;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}
