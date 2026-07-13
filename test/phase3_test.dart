import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_audio/services/audio_capture_service.dart';
import 'package:sync_audio/services/audio_playback_service.dart';
import 'package:sync_audio/services/udp_audio_service.dart';

class FakeAudioPlaybackService implements AudioPlaybackService {
  final packets = StreamController<Uint8List>.broadcast();
  bool _isPlaying = false;

  @override
  bool get isPlaying => _isPlaying;

  @override
  Future<void> start() async => _isPlaying = true;

  @override
  Future<void> writePcm(Uint8List bytes) async => packets.add(bytes);

  @override
  Future<void> stop() async => _isPlaying = false;

  Future<void> dispose() => packets.close();
}

class FakeAudioCaptureService implements AudioCaptureService {
  final chunks = StreamController<Uint8List>.broadcast();
  bool _isCapturing = false;

  @override
  Stream<Uint8List> get pcmChunks => chunks.stream;

  @override
  bool get isCapturing => _isCapturing;

  @override
  Future<void> start() async => _isCapturing = true;

  @override
  Future<void> stop() async => _isCapturing = false;

  void emit(Uint8List pcm) => chunks.add(pcm);

  Future<void> dispose() => chunks.close();
}

void main() {
  test(
    'UDP audio service delivers PCM to the receiver playback service',
    () async {
      final playback = FakeAudioPlaybackService();
      final receiverCapture = FakeAudioCaptureService();
      final hostCapture = FakeAudioCaptureService();
      final receiver = UdpAudioService(
        playbackService: playback,
        captureService: receiverCapture,
      );
      final host = UdpAudioService(
        playbackService: playback,
        captureService: hostCapture,
      );
      final packet = playback.packets.stream.first;

      await receiver.startReceiver(port: 5052);
      await host.startStreaming(ipAddresses: ['127.0.0.1'], port: 5052);
      hostCapture.emit(Uint8List(1024 * 2));

      final pcm = await packet.timeout(const Duration(seconds: 2));
      expect(pcm.length, 1024 * 2);
      expect(playback.isPlaying, isTrue);

      await host.dispose();
      await receiver.dispose();
      await playback.dispose();
      await receiverCapture.dispose();
      await hostCapture.dispose();
    },
  );
}
