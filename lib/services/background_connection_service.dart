import 'package:flutter/services.dart';

class BackgroundConnectionService {
  static const _channel = MethodChannel('sync_audio/background_service');

  static Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } on MissingPluginException {
      // Background connection priority is Android-specific.
    } on PlatformException {
      // Do not interrupt a connection operation if Android rejects the service.
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Background connection priority is Android-specific.
    } on PlatformException {
      // Best-effort cleanup.
    }
  }
}
