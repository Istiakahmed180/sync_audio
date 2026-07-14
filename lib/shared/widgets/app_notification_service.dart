import 'package:flutter/services.dart';

class AppNotificationService {
  static const _channel = MethodChannel('sync_audio/notifications');

  static Future<void> show({
    required String title,
    required String message,
    int id = 1001,
  }) async {
    try {
      await _channel.invokeMethod<void>('show', {
        'title': title,
        'message': message,
        'id': id,
      });
    } on MissingPluginException {
      // Notifications are Android-specific.
    } on PlatformException {
      // A notification must not interrupt an audio or connection operation.
    }
  }
}
