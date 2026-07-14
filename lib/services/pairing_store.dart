import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class PairingStore {
  Future<String?> readToken();

  Future<void> writeToken(String token);
}

class SharedPrefsPairingStore implements PairingStore {
  static const _key = 'sync_audio_pairing_token';
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

  static String generateToken() => SharedPrefsPairingStore.generateToken();
}
