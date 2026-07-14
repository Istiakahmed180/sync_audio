import 'dart:math';

import 'package:flutter/services.dart';

abstract class PairingStore {
  Future<String?> readToken();

  Future<void> writeToken(String token);
}

class AndroidPairingStore implements PairingStore {
  static const _channel = MethodChannel('sync_audio/pairing');

  @override
  Future<String?> readToken() async {
    try {
      return await _channel.invokeMethod<String>('read');
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> writeToken(String token) async {
    try {
      await _channel.invokeMethod<void>('write', token);
    } on MissingPluginException {
      // Non-Android builds use an ephemeral token for development only.
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
