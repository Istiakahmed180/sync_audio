import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sync_audio/models/receiver_session.dart';
import 'package:sync_audio/services/audio_codec.dart';
import 'package:sync_audio/services/audio_packet_codec.dart';
import 'package:sync_audio/services/connection_service.dart';

void main() {
  test('audio packet codec preserves packet type, timestamp, and payload', () {
    final encoded = AudioPacketCodec.encode(
      type: AudioPacketType.clockOffset,
      sequence: 12,
      timestampMicros: -1234,
      payload: Uint8List.fromList([1, 2, 3]),
    );
    final decoded = AudioPacketCodec.decode(encoded);

    expect(decoded?.type, AudioPacketType.clockOffset);
    expect(decoded?.sequence, 12);
    expect(decoded?.timestampMicros, -1234);
    expect(decoded?.payload, [1, 2, 3]);
    expect(decoded?.codecType, AudioCodecType.pcm16);
  });

  test('TCP control service accepts multiple host connections', () async {
    final receiver = TcpConnectionService();
    final hostOne = TcpConnectionService();
    final hostTwo = TcpConnectionService();
    await receiver.startServer(port: 5053);

    await Future.wait([
      hostOne.connect(ipAddress: '127.0.0.1', port: 5053),
      hostTwo.connect(ipAddress: '127.0.0.1', port: 5053),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      receiver.controlSessions
          .where(
            (session) =>
                session.controlStatus == ControlConnectionStatus.connected,
          )
          .length,
      2,
    );

    final messages = receiver.receivedMessages.take(2).toList();
    await hostOne.sendMessage('receiver one');
    await hostTwo.sendMessage('receiver two');
    expect((await messages).toSet(), {'receiver one', 'receiver two'});

    await hostOne.dispose();
    await hostTwo.dispose();
    await receiver.dispose();
  });

  test('pairing rejection stops reconnect instead of looping', () async {
    final receiver = TcpConnectionService()..setPairingToken('123456');
    final host = TcpConnectionService()..setPairingToken('wrong-code');
    await receiver.startServer(port: 5057);
    final error = host.errors.firstWhere(
      (message) => message.contains('Pairing rejected'),
    );

    await host.connect(ipAddress: '127.0.0.1', port: 5057);
    expect(await error.timeout(const Duration(seconds: 2)), contains('again'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.isConnected, isFalse);

    await host.dispose();
    await receiver.dispose();
  });
}
