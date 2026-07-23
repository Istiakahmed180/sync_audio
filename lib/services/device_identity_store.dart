import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentityStore {
  static const _key = 'sync_audio_device_id';

  Future<String> getOrCreate() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final values = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .toList(growable: false);
    return _save(
      prefs,
      '${values.sublist(0, 4).join()}-${values.sublist(4, 6).join()}-'
      '${values.sublist(6, 8).join()}-${values.sublist(8, 10).join()}-'
      '${values.sublist(10).join()}',
    );
  }

  Future<String> _save(SharedPreferences prefs, String id) async {
    await prefs.setString(_key, id);
    return id;
  }
}
