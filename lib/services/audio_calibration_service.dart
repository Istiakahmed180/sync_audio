import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:record/record.dart';

class AudioCalibrationService {
  AudioRecorder? _record;
  StreamSubscription? _subscription;

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
    _record ??= AudioRecorder();
    if (!await _record!.hasPermission()) {
      return null;
    }

    final completer = Completer<int?>();
    final startTime = DateTime.now();

    const threshold = 0.3; // Normalized amplitude threshold for detection

    try {
      final stream = await _record!.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );

      _subscription = stream.listen(
        (data) {
          if (completer.isCompleted) return;

          final int16Data = Int16List.view(
            data.buffer,
            data.offsetInBytes,
            data.length ~/ 2,
          );

          for (int i = 0; i < int16Data.length; i++) {
            final sample = int16Data[i].abs() / 32768.0;
            if (sample > threshold) {
              final detectTime = DateTime.now();
              final offset = detectTime.difference(startTime).inMicroseconds;
              _stop();
              if (!completer.isCompleted) completer.complete(offset);
              break;
            }
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.complete(null);
          _stop();
        },
      );

      Timer(timeout, () {
        if (!completer.isCompleted) {
          _stop();
          completer.complete(null);
        }
      });
    } catch (e) {
      if (!completer.isCompleted) completer.complete(null);
      _stop();
    }

    return completer.future;
  }

  void _stop() {
    _subscription?.cancel();
    _subscription = null;
    _record?.stop();
  }
}
