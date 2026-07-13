import 'dart:math';
import 'dart:typed_data';

class AudioToneGenerator {
  AudioToneGenerator({
    this.sampleRate = 44100,
    this.frequency = 440,
    this.framesPerPacket = 1024,
  });

  final int sampleRate;
  final int frequency;
  final int framesPerPacket;
  int _sequence = 0;

  Uint8List nextPacket() {
    final bytes = Uint8List(4 + framesPerPacket * 2);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, _sequence++, Endian.big);
    final startFrame = (_sequence - 1) * framesPerPacket;
    for (var frame = 0; frame < framesPerPacket; frame++) {
      final phase = 2 * pi * frequency * (startFrame + frame) / sampleRate;
      final sample = (sin(phase) * 0.2 * 32767).round();
      data.setInt16(4 + frame * 2, sample, Endian.little);
    }
    return bytes;
  }
}
