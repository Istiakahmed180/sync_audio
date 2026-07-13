abstract class AudioPlaybackService {
  Future<void> start();
  Future<void> stop();
  bool get isPlaying;
}

class PlaceholderAudioPlaybackService implements AudioPlaybackService {
  @override
  bool isPlaying = false;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}
