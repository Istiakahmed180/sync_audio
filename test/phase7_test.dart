import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:sync_audio/models/control_command.dart';
import 'package:sync_audio/services/audio_codec.dart';
import 'package:sync_audio/services/audio_packet_codec.dart';
import 'package:sync_audio/services/audio_fec_codec.dart';
import 'package:sync_audio/services/adaptive_jitter_buffer.dart';
import 'package:sync_audio/services/connection_service.dart';
import 'package:sync_audio/services/latency_metrics.dart';
import 'package:sync_audio/services/secure_transport.dart';
import 'package:sync_audio/services/synchronization_service.dart';

void main() {
  test('FEC parity recovers one missing PCM payload', () {
    final payloads = List<Uint8List>.generate(
      AudioFecCodec.groupSize,
      (index) => Uint8List.fromList([index + 1, index + 2, index + 3]),
    );
    final parity = AudioFecCodec.decode(
      AudioFecCodec.encode(
        groupStartSequence: 20,
        timestampsMicros: [100, 200, 300, 400],
        payloads: payloads,
      ),
    );
    expect(parity, isNotNull);
    final recovered = Uint8List.fromList(parity!.parity);
    for (final index in [0, 1, 3]) {
      for (var byte = 0; byte < recovered.length; byte++) {
        recovered[byte] ^= payloads[index][byte];
      }
    }
    expect(recovered, payloads[2]);
    expect(parity.timestampsMicros[2], 300);
  });

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

  test('adaptive jitter buffer orders packets and handles loss', () {
    final buffer = AdaptiveJitterBuffer(mode: LatencyMode.ultraLow);
    expect(
      buffer.add(
        JitterAudioPacket(
          sequence: 2,
          timestampMicros: 100,
          payload: Uint8List.fromList([2]),
          arrivalMicros: 20,
        ),
      ),
      isTrue,
    );
    expect(buffer.add(_packet(1, 90, 10)), isTrue);
    expect(buffer.takeReady(90)?.sequence, 1);
    expect(buffer.takeReady(100)?.sequence, 2);

    buffer.add(
      JitterAudioPacket(
        sequence: 4,
        timestampMicros: 200,
        payload: Uint8List.fromList([4]),
        arrivalMicros: 30,
      ),
    );
    expect(buffer.takeReady(200), isNull);
    expect(buffer.takeReady(30231), isNull);
    expect(buffer.underruns, 1);
  });

  test('latency metrics expose a redacted bounded snapshot', () {
    final metrics = LatencyMetricsTracker();
    metrics.captureStarted();
    metrics.packetArrived();
    metrics.packetLost();
    metrics.setDrift(estimatedPpm: 420, appliedPpm: 200);
    final snapshot = metrics.snapshot();
    expect(snapshot.packetLossPercent, 50);
    expect(snapshot.appliedDriftCorrectionPpm, 200);
    expect(snapshot.toRedactedMap().containsKey('pairingToken'), isFalse);
    expect(snapshot.toRedactedMap().containsKey('rawAudio'), isFalse);
  });

  test('clock synchronization filters samples per session and bounds drift', () async {
    final service = ClockSynchronizationService();
    await service.synchronize();
    expect(service.isSynchronizing, isTrue);

    final first = service.recordSample(
      sessionId: 'receiver-a',
      sentAtMicros: 1000,
      receivedAtMicros: 3000,
      remoteTimestampMicros: 2500,
    );
    expect(first.roundTripTimeMicros, 2000);
    expect(first.offsetMicros, 500);

    final second = service.recordSample(
      sessionId: 'receiver-a',
      sentAtMicros: 1_001_000,
      receivedAtMicros: 1_003_000,
      remoteTimestampMicros: 1_002_500,
    );
    expect(second.offsetMicros, 500);
    expect(second.driftPpm.abs(), lessThanOrEqualTo(5000));

    final independent = service.recordSample(
      sessionId: 'receiver-b',
      sentAtMicros: 1000,
      receivedAtMicros: 5000,
      remoteTimestampMicros: 4000,
    );
    expect(independent.offsetMicros, 1000);

    service.resetSession('receiver-a');
    await service.stop();
    expect(service.isSynchronizing, isFalse);
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

JitterAudioPacket _packet(int sequence, int timestamp, int arrival) =>
    JitterAudioPacket(
      sequence: sequence,
      timestampMicros: timestamp,
      payload: Uint8List.fromList([sequence]),
      arrivalMicros: arrival,
    );
