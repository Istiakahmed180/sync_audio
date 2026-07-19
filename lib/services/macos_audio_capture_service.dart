import 'package:flutter/services.dart';

import 'audio_capture_service.dart';

class MacosAudioCaptureService implements AudioCaptureService {
  static const _controlChannel = MethodChannel('sync_audio/macos_audio_capture');
  static const _streamChannel = EventChannel('sync_audio/macos_audio_stream');

  @override
  Stream<Uint8List> get pcmChunks =>
      _streamChannel.receiveBroadcastStream().map((chunk) {
        if (chunk is Uint8List) return chunk;
        if (chunk is ByteData) {
          return chunk.buffer.asUint8List(
            chunk.offsetInBytes,
            chunk.lengthInBytes,
          );
        }
        try {
          return Uint8List.fromList(List<int>.from(chunk as List<dynamic>));
        } catch (_) {
          return Uint8List(0);
        }
      }).where((bytes) => bytes.isNotEmpty);

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
