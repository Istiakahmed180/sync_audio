import 'package:flutter/services.dart';

abstract class AudioPlaybackService {
  Future<void> start();
  Future<void> writePcm(Uint8List bytes);
  Future<void> stop();
  bool get isPlaying;
}

class AndroidAudioTrackPlaybackService implements AudioPlaybackService {
  static const _channel = MethodChannel('sync_audio/audio_track');
  bool _isPlaying = false;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Future<void> start() async {
    await _channel.invokeMethod<void>('initialize');
    _isPlaying = true;
  }

  @override
  Future<void> writePcm(Uint8List bytes) async {
    if (!_isPlaying) return;
    await _channel.invokeMethod<void>('writePcm', <String, Object>{
      'data': bytes,
    });
  }

  @override
  Future<void> stop() async {
    if (!_isPlaying) return;
    await _channel.invokeMethod<void>('stop');
    _isPlaying = false;
  }
}

class PlaceholderAudioPlaybackService implements AudioPlaybackService {
  @override
  bool isPlaying = false;
  @override
  Future<void> start() async => isPlaying = true;
  @override
  Future<void> writePcm(Uint8List bytes) async {}
  @override
  Future<void> stop() async => isPlaying = false;
}
