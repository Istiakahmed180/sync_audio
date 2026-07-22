import 'package:flutter/services.dart';

class AppNotificationService {
  static const _channel = MethodChannel('sync_audio/notifications');
  static const _actions = EventChannel('sync_audio/notification_actions');

  static Stream<String> get actions => _actions
      .receiveBroadcastStream()
      .where((value) => value is String)
      .cast<String>();

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

  static Future<void> showMedia({
    required String title,
    required String message,
    required bool isPlaying,
    required bool isMuted,
    int id = 1001,
  }) async {
    try {
      await _channel.invokeMethod<void>('showMedia', {
        'title': title,
        'message': message,
        'isPlaying': isPlaying,
        'isMuted': isMuted,
        'id': id,
      });
    } on MissingPluginException {
      // Media controls are Android-specific.
    } on PlatformException {
      // Notification controls are best-effort.
    }
  }
}
