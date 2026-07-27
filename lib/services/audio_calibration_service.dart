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
    FutureOr<void> Function()? onReady,
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
      final reference = Int16List.view(generateChirp().buffer);
      final samples = <int>[];

      Future<void> finish(int? result) async {
        if (finishing) return;
        finishing = true;
        await _stop();
        if (!completer.isCompleted) completer.complete(result);
      }

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

          // Audio plugins may deliver chunks whose Uint8List starts at an
          // odd byte offset. Int16List.view requires 2-byte alignment.
          final alignedData = data.offsetInBytes.isEven
              ? data
              : Uint8List.fromList(data);
          final sampleByteLength = alignedData.lengthInBytes & ~1;
          if (sampleByteLength == 0) return;
          final int16Data = Int16List.view(
            alignedData.buffer,
            alignedData.offsetInBytes,
            sampleByteLength ~/ 2,
          );
          samples.addAll(int16Data);
          if (samples.length > reference.length) {
            samples.removeRange(0, samples.length - reference.length);
          }
          if (samples.length < reference.length) return;

          // Match the generated chirp rather than treating any loud sound as
          // calibration audio. Downsampling the correlation keeps this cheap
          // enough for microphone callbacks.
          var dot = 0.0;
          var referenceEnergy = 0.0;
          var sampleEnergy = 0.0;
          for (var i = 0; i < reference.length; i += 8) {
            final expected = reference[i].toDouble();
            final actual = samples[i].toDouble();
            dot += expected * actual;
            referenceEnergy += expected * expected;
            sampleEnergy += actual * actual;
          }
          final denominator = math.sqrt(referenceEnergy * sampleEnergy);
          final correlation = denominator == 0 ? 0 : dot / denominator;
          if (correlation >= 0.35) {
            final detectTime = DateTime.now();
            final elapsed =
                detectTime.difference(startTime).inMicroseconds -
                const Duration(milliseconds: 300).inMicroseconds;
            unawaited(finish(math.max(0, elapsed)));
          }
        }, onError: (_) => unawaited(finish(null)));

        if (onReady != null) await onReady();
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
