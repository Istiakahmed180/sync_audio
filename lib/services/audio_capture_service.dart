import 'package:flutter/services.dart';

abstract class AudioCaptureService {
  Stream<Uint8List> get pcmChunks;
  bool get isCapturing;

  Future<void> start();
  Future<void> stop();
}

class AndroidSystemAudioCaptureService implements AudioCaptureService {
  static const _controlChannel = MethodChannel(
    'sync_audio/system_audio_capture',
  );
  static const _streamChannel = EventChannel('sync_audio/system_audio_stream');

  @override
  Stream<Uint8List> get pcmChunks =>
      _streamChannel.receiveBroadcastStream().map(
        (chunk) => Uint8List.fromList(List<int>.from(chunk as List<dynamic>)),
      );

  bool _isCapturing = false;

  @override
  bool get isCapturing => _isCapturing;

  @override
  Future<void> start() async {
    if (_isCapturing) return;
    await _controlChannel.invokeMethod<void>('start');
    _isCapturing = true;
  }

  @override
  Future<void> stop() async {
    if (!_isCapturing) return;
    await _controlChannel.invokeMethod<void>('stop');
    _isCapturing = false;
  }
}

class PlaceholderAudioCaptureService implements AudioCaptureService {
  @override
  Stream<Uint8List> get pcmChunks => const Stream<Uint8List>.empty();

  @override
  bool isCapturing = false;

  @override
  Future<void> start() async => isCapturing = true;

  @override
  Future<void> stop() async => isCapturing = false;
}
