import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:sync_audio/models/control_command.dart';
import 'package:sync_audio/services/audio_codec.dart';
import 'package:sync_audio/services/audio_packet_codec.dart';
import 'package:sync_audio/services/connection_service.dart';
import 'package:sync_audio/services/secure_transport.dart';

void main() {
  test('PCM codec round-trips and unsupported Opus fails explicitly', () async {
    final pcm = Uint8List.fromList([1, 2, 3, 4]);
    expect(await Pcm16AudioEncoder().encode(pcm), pcm);
    expect(await Pcm16AudioDecoder().decode(pcm), pcm);
    expect(
      UnsupportedOpusEncoder().encode(pcm),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('control protocol parses the supported wire commands', () {
    expect(
      ControlCommand.parse('STREAM_START:session-1:1234')?.type,
      ControlCommandType.streamStart,
    );
    expect(
      ControlCommand.parse('ERROR:BUFFER_UNDERRUN:packet lost')?.arguments,
      ['BUFFER_UNDERRUN', 'packet lost'],
    );
    expect(ControlCommand.parse('PONG:bad'), isNull);
  });

  test('encrypted audio packets reject tampering and replay', () async {
    final key = await SessionKeyService().derive(
      pairingToken: '123456',
      sessionId: 'session-1',
    );
    final packet = AudioPacketCodec.encode(
      type: AudioPacketType.pcmAudio,
      sequence: 1,
      timestampMicros: 42,
      payload: Uint8List.fromList([1, 2, 3]),
    );
    final encrypted = await EncryptedAudioPacketCodec.encrypt(
      packet: packet,
      key: key,
      sessionId: 'session-1',
    );
    final guard = ReplayGuard();
    expect(
      await EncryptedAudioPacketCodec.decrypt(
        packet: encrypted,
        key: key,
        sessionId: 'session-1',
        replayGuard: guard,
      ),
      packet,
    );
    expect(
      EncryptedAudioPacketCodec.decrypt(
        packet: encrypted,
        key: key,
        sessionId: 'session-1',
        replayGuard: guard,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('TCP pairing and PING/PONG emit typed control events', () async {
    final receiver = TcpConnectionService()..setPairingToken('123456');
    final host = TcpConnectionService()..setPairingToken('123456');
    await receiver.startServer(port: 5055);
    final hello = receiver.controlEvents.firstWhere(
      (event) => event.command.type == ControlCommandType.hello,
    );

    await host.connect(ipAddress: '127.0.0.1', port: 5055);
    final event = await hello.timeout(const Duration(seconds: 2));
    expect(event.command.arguments, hasLength(2));
    expect(receiver.controlSessions, hasLength(1));

    await host.dispose();
    await receiver.dispose();
  });
}
