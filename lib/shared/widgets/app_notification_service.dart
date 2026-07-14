import 'package:flutter/services.dart';

class AppNotificationService {
  static const _channel = MethodChannel('sync_audio/notifications');

  static Future<void> show({
    required String title,
    required String message,
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'title': title,
        'message': message,
      });
    } on MissingPluginException {
      // Notifications are Android-specific.
    } on PlatformException {
      // A notification must not interrupt an audio or connection operation.
    }
  }
}
