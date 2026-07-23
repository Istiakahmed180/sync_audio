import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class PairingStore {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<DateTime?> readTokenIssuedAt();

  Future<void> writeTokenIssuedAt(DateTime issuedAt);

  Future<List<String>> readTrustedDevices();

  Future<void> addTrustedDevice(String deviceAddress);

  Future<void> revokeTrustedDevice(String deviceAddress);
}

class SharedPrefsPairingStore implements PairingStore {
  static const _key = 'sync_audio_pairing_token';
  static const _issuedAtKey = 'sync_audio_pairing_token_issued_at';
  static const _trustedDevicesKey = 'sync_audio_trusted_devices';
  String? _inMemoryToken;

  @override
  Future<String?> readToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key) ?? _inMemoryToken;
    } catch (_) {
      return _inMemoryToken;
    }
  }

  @override
  Future<void> writeToken(String token) async {
    _inMemoryToken = token;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, token);
    } catch (_) {
      // Fallback: token stored in memory only.
    }
  }

  @override
  Future<DateTime?> readTokenIssuedAt() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_issuedAtKey);
      return value == null ? null : DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeTokenIssuedAt(DateTime issuedAt) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_issuedAtKey, issuedAt.toIso8601String());
    } catch (_) {}
  }

  @override
  Future<List<String>> readTrustedDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_trustedDevicesKey) ?? const [])
          .where((value) => value.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> addTrustedDevice(String deviceAddress) async {
    final address = deviceAddress.trim();
    if (address.isEmpty) return;
    try {
      final devices = (await readTrustedDevices()).toSet()..add(address);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_trustedDevicesKey, devices.toList());
    } catch (_) {}
  }

  @override
  Future<void> revokeTrustedDevice(String deviceAddress) async {
    try {
      final devices = (await readTrustedDevices()).toSet()
        ..remove(deviceAddress.trim());
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_trustedDevicesKey, devices.toList());
    } catch (_) {}
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
  static const _channel = MethodChannel('sync_audio/pairing');
  final SharedPrefsPairingStore _fallback = SharedPrefsPairingStore();

  @override
  Future<String?> readToken() async {
    try {
      return await _channel.invokeMethod<String>('read') ??
          await _fallback.readToken();
    } on MissingPluginException {
      return _fallback.readToken();
    }
  }

  @override
  Future<void> writeToken(String token) async {
    try {
      await _channel.invokeMethod<void>('write', token);
    } on MissingPluginException {
      await _fallback.writeToken(token);
    }
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

  static String generateToken() => SharedPrefsPairingStore.generateToken();
}
