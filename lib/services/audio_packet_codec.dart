import 'dart:typed_data';

import 'audio_codec.dart';

enum AudioPacketType {
  pcmAudio,
  clockSyncRequest,
  clockSyncResponse,
  clockOffset,
  clockDrift,
}

class AudioPacket {
  const AudioPacket({
    required this.type,
    required this.sequence,
    required this.timestampMicros,
    required this.payload,
    this.codecType = AudioCodecType.pcm16,
  });

  final AudioPacketType type;
  final int sequence;
  final int timestampMicros;
  final Uint8List payload;
  final AudioCodecType codecType;
}

class AudioPacketCodec {
  static const headerBytes = 17;
  static const legacyHeaderBytes = 16;
  static const _magic = 0x5341;
  static const _version = 2;

  static Uint8List encode({
    required AudioPacketType type,
    required int sequence,
    required int timestampMicros,
    AudioCodecType codecType = AudioCodecType.pcm16,
    Uint8List? payload,
  }) {
    final body = payload ?? Uint8List(0);
    final bytes = Uint8List(headerBytes + body.length);
    final data = ByteData.sublistView(bytes);
    data.setUint16(0, _magic, Endian.big);
    data.setUint8(2, _version);
    data.setUint8(3, type.index + 1);
    data.setUint8(4, codecType.index + 1);
    data.setUint32(5, sequence & 0xFFFFFFFF, Endian.big);
    data.setInt64(9, timestampMicros, Endian.big);
    bytes.setRange(headerBytes, bytes.length, body);
    return bytes;
  }

  static AudioPacket? decode(List<int> bytes) {
    if (bytes.length < legacyHeaderBytes) {
      return null;
    }
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    if (data.getUint16(0, Endian.big) != _magic) {
      return null;
    }
    final version = data.getUint8(2);
    final isLegacy = version == 1;
    if (!isLegacy && version != _version) return null;
    final typeValue = data.getUint8(3) - 1;
    if (typeValue < 0 || typeValue >= AudioPacketType.values.length) {
      return null;
    }
    final codecValue = isLegacy ? 1 : data.getUint8(4);
    if (codecValue < 1 || codecValue > AudioCodecType.values.length) {
      return null;
    }
    final payloadOffset = isLegacy ? legacyHeaderBytes : headerBytes;
    return AudioPacket(
      type: AudioPacketType.values[typeValue],
      codecType: AudioCodecType.values[codecValue - 1],
      sequence: data.getUint32(isLegacy ? 4 : 5, Endian.big),
      timestampMicros: data.getInt64(isLegacy ? 8 : 9, Endian.big),
      payload: Uint8List.fromList(bytes.skip(payloadOffset).toList()),
    );
  }
}
