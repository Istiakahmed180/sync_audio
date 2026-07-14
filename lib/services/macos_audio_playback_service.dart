import 'package:flutter/services.dart';

import 'audio_playback_service.dart';

class MacosAudioPlaybackService implements AudioPlaybackService {
  static const _channel = MethodChannel('sync_audio/macos_audio_playback');
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
