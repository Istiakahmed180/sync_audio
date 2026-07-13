import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_audio/services/audio_playback_service.dart';
import 'package:sync_audio/services/audio_tone_generator.dart';
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

void main() {
  test('tone generator creates sequenced 16-bit mono PCM packets', () {
    final generator = AudioToneGenerator();
    final first = generator.nextPacket();
    final second = generator.nextPacket();

    expect(first.length, 4 + 1024 * 2);
    expect(second.length, first.length);
    expect(ByteData.sublistView(first).getUint32(0), 0);
    expect(ByteData.sublistView(second).getUint32(0), 1);
    expect(first.sublist(4).any((byte) => byte != 0), isTrue);
  });

  test(
    'UDP audio service delivers PCM to the receiver playback service',
    () async {
      final playback = FakeAudioPlaybackService();
      final receiver = UdpAudioService(playbackService: playback);
      final host = UdpAudioService(playbackService: playback);
      final packet = playback.packets.stream.first;

      await receiver.startReceiver(port: 5052);
      await host.startStreaming(ipAddress: '127.0.0.1', port: 5052);

      final pcm = await packet.timeout(const Duration(seconds: 2));
      expect(pcm.length, 1024 * 2);
      expect(playback.isPlaying, isTrue);

      await host.dispose();
      await receiver.dispose();
      await playback.dispose();
    },
  );
}
