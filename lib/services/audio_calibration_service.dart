import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

class AudioCalibrationService {
  AudioRecorder? _record;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _timeoutTimer;
  Future<void> _lifecycle = Future<void>.value();

  // Chirp detection parameters
  static const int sampleRate = 44100;
  static const double chirpDuration = 0.3;
  static const double startFreq = 2000.0;
  static const double endFreq = 6000.0;

  /// Generates a log-chirp signal as PCM16 bytes.
  static Uint8List generateChirp() {
    final numSamples = (sampleRate * chirpDuration).toInt();
    final pcm = Int16List(numSamples);

    // Log-chirp formula
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final k = math.pow(endFreq / startFreq, 1 / chirpDuration);
      final phase =
          2 * math.pi * startFreq * (math.pow(k, t) - 1) / math.log(k);
      pcm[i] = (math.sin(phase) * 32767).toInt();
    }

    return pcm.buffer.asUint8List();
  }

  /// Starts listening for the chirp on the microphone.
  Future<int?> listenForChirp({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final operation = _lifecycle.then((_) async {
      await _stop();
      final record = AudioRecorder();
      _record = record;
      if (!await record.hasPermission()) {
        await _stop();
        return null;
      }

      final completer = Completer<int?>();
      final startTime = DateTime.now();
      var finishing = false;

      Future<void> finish(int? result) async {
        if (finishing) return;
        finishing = true;
        await _stop();
        if (!completer.isCompleted) completer.complete(result);
      }

      const threshold = 0.3;
      try {
        final stream = await record.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: sampleRate,
            numChannels: 1,
          ),
        );

        _subscription = stream.listen((data) {
          if (finishing || data.length < 2) return;

          final int16Data = Int16List.view(
            data.buffer,
            data.offsetInBytes,
            data.length ~/ 2,
          );

          for (int i = 0; i < int16Data.length; i++) {
            final sample = int16Data[i].abs() / 32768.0;
            if (sample > threshold) {
              final detectTime = DateTime.now();
              unawaited(
                finish(detectTime.difference(startTime).inMicroseconds),
              );
              break;
            }
          }
        }, onError: (_) => unawaited(finish(null)));

        _timeoutTimer = Timer(timeout, () => unawaited(finish(null)));
        return completer.future;
      } catch (_) {
        await finish(null);
        return null;
      }
    });
    _lifecycle = operation.then<void>((_) {}).catchError((_) {});
    return operation;
  }

  Future<void> _stop() async {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
    final record = _record;
    _record = null;
    await record?.stop();
    await record?.dispose();
  }
}
