import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'audio_packet_codec.dart';

class SessionKeyService {
  static final _hash = Sha256();

  Future<SecretKey> derive({
    required String pairingToken,
    required String sessionId,
  }) async {
    final material = utf8.encode('sync_audio/v1|$sessionId|$pairingToken');
    final digest = await _hash.hash(material);
    return SecretKey(digest.bytes);
  }
}

class EncryptedAudioPacketCodec {
  static const _magic = <int>[0x53, 0x45, 0x01];
  static final _cipher = AesGcm.with256bits();
  static final _hash = Sha256();

  static Future<Uint8List> encrypt({
    required Uint8List packet,
    required SecretKey key,
    required String sessionId,
  }) async {
    final decoded = AudioPacketCodec.decode(packet);
    if (decoded == null) throw const FormatException('Invalid audio packet.');
    final nonce = await _nonce(decoded, sessionId);
    final box = await _cipher.encrypt(
      packet,
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(sessionId),
    );
    return Uint8List.fromList([
      ..._magic,
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  static Future<Uint8List> decrypt({
    required Uint8List packet,
    required SecretKey key,
    required String sessionId,
    ReplayGuard? replayGuard,
  }) async {
    if (packet.length < _magic.length + 12 + 16 || !_hasMagic(packet)) {
      throw const FormatException('Invalid encrypted audio packet.');
    }
    final nonce = packet.sublist(3, 15);
    final nonceId = base64Url.encode(nonce);
    if (replayGuard?.accept(nonceId) == false) {
      throw const FormatException('Replay or duplicate audio packet.');
    }
    final cipherEnd = packet.length - 16;
    final box = SecretBox(
      packet.sublist(15, cipherEnd),
      nonce: nonce,
      mac: Mac(packet.sublist(cipherEnd)),
    );
    return Uint8List.fromList(
      await _cipher.decrypt(box, secretKey: key, aad: utf8.encode(sessionId)),
    );
  }

  static bool isEncrypted(Uint8List packet) =>
      packet.length >= 3 && _hasMagic(packet);

  static bool _hasMagic(Uint8List packet) =>
      packet[0] == _magic[0] &&
      packet[1] == _magic[1] &&
      packet[2] == _magic[2];

  static final _random = Random.secure();

  static Future<List<int>> _nonce(AudioPacket packet, String sessionId) async {
    final digest = await _hash.hash(utf8.encode(sessionId));
    final nonce = Uint8List(12);
    nonce.setRange(0, 3, digest.bytes);
    nonce[3] = packet.type.index;
    ByteData.sublistView(nonce).setUint64(4, packet.sequence, Endian.big);
    nonce[0] ^= _random.nextInt(256);
    return nonce;
  }
}

class ReplayGuard {
  ReplayGuard({this.maxEntries = 4096});

  final int maxEntries;
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();

  bool accept(String nonce) {
    if (!_seen.add(nonce)) return false;
    if (_seen.length > maxEntries) {
      _seen.remove(_seen.first);
    }
    return true;
  }
}

class EncryptedControlChannel {
  EncryptedControlChannel({
    required this.key,
    required this.sessionId,
    required this.role,
  });

  static final _cipher = AesGcm.with256bits();
  static final _hash = Sha256();
  final SecretKey key;
  final String sessionId;
  final String role;
  final ReplayGuard replayGuard = ReplayGuard();
  int _counter = 0;

  Future<String> encrypt(String line) async {
    final digest = await _hash.hash(utf8.encode('$sessionId|$role'));
    final nonce = Uint8List(12)..setRange(0, 4, digest.bytes);
    final counterBytes = ByteData(8)..setUint64(0, _counter++, Endian.big);
    nonce.setRange(4, 12, counterBytes.buffer.asUint8List());
    final box = await _cipher.encrypt(
      utf8.encode(line),
      secretKey: key,
      nonce: nonce,
      aad: utf8.encode(sessionId),
    );
    return 'ENC:${base64Url.encode(<int>[...nonce, ...box.cipherText, ...box.mac.bytes])}';
  }

  Future<String> decrypt(String line) async {
    if (!line.startsWith('ENC:')) {
      throw const FormatException('Encrypted control frame is missing.');
    }
    final bytes = base64Url.decode(line.substring(4));
    if (bytes.length < 12 + 16) {
      throw const FormatException('Encrypted control frame is invalid.');
    }
    final nonce = bytes.sublist(0, 12);
    if (!replayGuard.accept(base64Url.encode(nonce))) {
      throw const FormatException('Encrypted control replay rejected.');
    }
    final cipherEnd = bytes.length - 16;
    final clear = await _cipher.decrypt(
      SecretBox(
        bytes.sublist(12, cipherEnd),
        nonce: nonce,
        mac: Mac(bytes.sublist(cipherEnd)),
      ),
      secretKey: key,
      aad: utf8.encode(sessionId),
    );
    return utf8.decode(clear);
  }
}
