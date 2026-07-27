import 'dart:math';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class PairingStore {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<DateTime?> readTokenIssuedAt();

  Future<void> writeTokenIssuedAt(DateTime issuedAt);

  Future<List<String>> readTrustedDevices();

  Future<void> addTrustedDevice(String deviceAddress);

  Future<void> revokeTrustedDevice(String deviceAddress);

  Future<Map<String, String>> readTrustedDeviceNames();

  Future<void> addTrustedDeviceName(String deviceAddress, String deviceName);
}

class SharedPrefsPairingStore implements PairingStore {
  static const _key = 'sync_audio_pairing_token';
  static const _issuedAtKey = 'sync_audio_pairing_token_issued_at';
  static const _trustedDevicesKey = 'sync_audio_trusted_devices';
  static const _trustedDeviceNamesKey = 'sync_audio_trusted_device_names';
  static const _storage = FlutterSecureStorage();
  String? _inMemoryToken;

  @override
  Future<String?> readToken() async {
    try {
      final value = await _storage.read(key: _key);
      if (value != null) return value;
    } catch (_) {
      // Fall through to migration/fallback below.
    }
    String? legacy;
    try {
      final prefs = await SharedPreferences.getInstance();
      legacy = prefs.getString(_key);
      if (legacy != null) await prefs.remove(_key);
    } catch (_) {
      return _inMemoryToken;
    }
    if (legacy != null) {
      _inMemoryToken = legacy;
      await _writeSecure(_key, legacy);
      return legacy;
    }
    return _inMemoryToken;
  }

  @override
  Future<void> writeToken(String token) async {
    _inMemoryToken = token;
    await _writeSecure(_key, token);
  }

  @override
  Future<DateTime?> readTokenIssuedAt() async {
    final value = await _readSecureWithLegacyMigration(_issuedAtKey);
    return value == null ? null : DateTime.tryParse(value);
  }

  @override
  Future<void> writeTokenIssuedAt(DateTime issuedAt) async {
    await _writeSecure(_issuedAtKey, issuedAt.toIso8601String());
  }

  @override
  Future<List<String>> readTrustedDevices() async {
    final value = await _readSecureWithLegacyMigration(_trustedDevicesKey);
    if (value == null) return const [];
    try {
      return (jsonDecode(value) as List)
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> addTrustedDevice(String deviceAddress) async {
    final address = deviceAddress.trim();
    if (address.isEmpty) return;
    final devices = (await readTrustedDevices()).toSet()..add(address);
    await _writeSecure(_trustedDevicesKey, jsonEncode(devices.toList()));
  }

  @override
  Future<void> revokeTrustedDevice(String deviceAddress) async {
    final devices = (await readTrustedDevices()).toSet()
      ..remove(deviceAddress.trim());
    await _writeSecure(_trustedDevicesKey, jsonEncode(devices.toList()));
  }

  @override
  Future<Map<String, String>> readTrustedDeviceNames() async {
    final raw = await _readSecureWithLegacyMigration(_trustedDeviceNamesKey);
    if (raw == null) return <String, String>{};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, String>{};
    }
  }

  @override
  Future<void> addTrustedDeviceName(
    String deviceAddress,
    String deviceName,
  ) async {
    final address = deviceAddress.trim();
    final name = deviceName.trim();
    if (address.isEmpty || name.isEmpty) return;
    final names = Map<String, String>.from(await readTrustedDeviceNames());
    names[address] = name;
    await _writeSecure(_trustedDeviceNamesKey, jsonEncode(names));
  }

  Future<String?> _readSecureWithLegacyMigration(String key) async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) return value;
    } catch (_) {
      // Fall through to the legacy SharedPreferences migration.
    }

    final SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
    String? legacy;
    if (key == _trustedDevicesKey) {
      final values = prefs.getStringList(key);
      if (values != null) legacy = jsonEncode(values);
    } else {
      legacy = prefs.getString(key);
    }
    if (legacy == null) return null;

    await _writeSecure(key, legacy);
    try {
      await prefs.remove(key);
    } catch (_) {}
    return legacy;
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Flutter tests and unsupported platforms retain a local fallback.
      try {
        final prefs = await SharedPreferences.getInstance();
        if (key == _trustedDevicesKey) {
          final values = (jsonDecode(value) as List)
              .whereType<String>()
              .toList();
          await prefs.setStringList(key, values);
        } else {
          await prefs.setString(key, value);
        }
      } catch (_) {}
    }
  }

  static String generateToken() {
    final random = Random.secure();
    return List<String>.generate(
      8,
      (_) => random.nextInt(10).toString(),
    ).join();
  }
}

class AndroidPairingStore implements PairingStore {
  final SharedPrefsPairingStore _fallback = SharedPrefsPairingStore();

  @override
  Future<String?> readToken() async {
    return _fallback.readToken();
  }

  @override
  Future<void> writeToken(String token) async {
    await _fallback.writeToken(token);
  }

  @override
  Future<DateTime?> readTokenIssuedAt() => _fallback.readTokenIssuedAt();

  @override
  Future<void> writeTokenIssuedAt(DateTime issuedAt) =>
      _fallback.writeTokenIssuedAt(issuedAt);

  @override
  Future<List<String>> readTrustedDevices() => _fallback.readTrustedDevices();

  @override
  Future<void> addTrustedDevice(String deviceAddress) =>
      _fallback.addTrustedDevice(deviceAddress);

  @override
  Future<void> revokeTrustedDevice(String deviceAddress) =>
      _fallback.revokeTrustedDevice(deviceAddress);

  @override
  Future<Map<String, String>> readTrustedDeviceNames() =>
      _fallback.readTrustedDeviceNames();

  @override
  Future<void> addTrustedDeviceName(String deviceAddress, String deviceName) =>
      _fallback.addTrustedDeviceName(deviceAddress, deviceName);

  static String generateToken() => SharedPrefsPairingStore.generateToken();
}
