import 'dart:typed_data';

/// XOR parity for a small group of equal-size PCM frames. It can recover one
/// missing frame without adding a retransmission round trip.
class AudioFecParity {
  const AudioFecParity({
    required this.groupStartSequence,
    required this.timestampsMicros,
    required this.parity,
  });

  final int groupStartSequence;
  final List<int> timestampsMicros;
  final Uint8List parity;
}

class AudioFecCodec {
  static const groupSize = 4;
  static const _metadataBytes = 4 + 1 + 2 + (groupSize * 8);

  static Uint8List encode({
    required int groupStartSequence,
    required List<int> timestampsMicros,
    required List<Uint8List> payloads,
  }) {
    if (timestampsMicros.length != groupSize || payloads.length != groupSize) {
      throw ArgumentError('FEC groups must contain exactly four frames.');
    }
    final maxLength = payloads.fold<int>(
      0,
      (maximum, payload) => payload.length > maximum ? payload.length : maximum,
    );
    if (maxLength > 0xFFFF) throw ArgumentError('FEC payload is too large.');
    final bytes = Uint8List(_metadataBytes + maxLength);
    final data = ByteData.sublistView(bytes);
    data.setUint32(0, groupStartSequence & 0xFFFFFFFF, Endian.big);
    data.setUint8(4, groupSize);
    data.setUint16(5, maxLength, Endian.big);
    for (var index = 0; index < groupSize; index++) {
      data.setInt64(7 + index * 8, timestampsMicros[index]);
    }
    for (final payload in payloads) {
      for (var index = 0; index < payload.length; index++) {
        bytes[_metadataBytes + index] ^= payload[index];
      }
    }
    return bytes;
  }

  static AudioFecParity? decode(Uint8List bytes) {
    if (bytes.length < _metadataBytes) return null;
    final data = ByteData.sublistView(bytes);
    if (data.getUint8(4) != groupSize) return null;
    final length = data.getUint16(5, Endian.big);
    if (bytes.length != _metadataBytes + length) return null;
    return AudioFecParity(
      groupStartSequence: data.getUint32(0, Endian.big),
      timestampsMicros: List<int>.generate(
        groupSize,
        (index) => data.getInt64(7 + index * 8),
      ),
      parity: Uint8List.sublistView(bytes, _metadataBytes),
    );
  }
}
