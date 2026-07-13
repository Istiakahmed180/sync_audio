import 'dart:typed_data';

enum AudioPacketType {
  pcmAudio,
  clockSyncRequest,
  clockSyncResponse,
  clockOffset,
}

class AudioPacket {
  const AudioPacket({
    required this.type,
    required this.sequence,
    required this.timestampMicros,
    required this.payload,
  });

  final AudioPacketType type;
  final int sequence;
  final int timestampMicros;
  final Uint8List payload;
}

class AudioPacketCodec {
  static const headerBytes = 16;
  static const _magic = 0x5341;
  static const _version = 1;

  static Uint8List encode({
    required AudioPacketType type,
    required int sequence,
    required int timestampMicros,
    Uint8List? payload,
  }) {
    final body = payload ?? Uint8List(0);
    final bytes = Uint8List(headerBytes + body.length);
    final data = ByteData.sublistView(bytes);
    data.setUint16(0, _magic, Endian.big);
    data.setUint8(2, _version);
    data.setUint8(3, type.index + 1);
    data.setUint32(4, sequence & 0xFFFFFFFF, Endian.big);
    data.setInt64(8, timestampMicros, Endian.big);
    bytes.setRange(headerBytes, bytes.length, body);
    return bytes;
  }

  static AudioPacket? decode(List<int> bytes) {
    if (bytes.length < headerBytes) {
      return null;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    if (data.getUint16(0, Endian.big) != _magic ||
        data.getUint8(2) != _version) {
      return null;
    }
    final typeValue = data.getUint8(3) - 1;
    if (typeValue < 0 || typeValue >= AudioPacketType.values.length) {
      return null;
    }
    return AudioPacket(
      type: AudioPacketType.values[typeValue],
      sequence: data.getUint32(4, Endian.big),
      timestampMicros: data.getInt64(8, Endian.big),
      payload: Uint8List.fromList(bytes.skip(headerBytes).toList()),
    );
  }
}
