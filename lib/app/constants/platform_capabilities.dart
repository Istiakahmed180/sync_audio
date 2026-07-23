import 'package:flutter/foundation.dart';

abstract final class PlatformCapabilities {
  static bool get supportsHost {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
      TargetPlatform.iOS ||
      TargetPlatform.linux ||
      TargetPlatform.fuchsia => false,
    };
  }

  static bool get supportsReceiver => !kIsWeb;

  static String get hostSupportMessage =>
      'Host is supported on Android, macOS, and Windows. '
      'iPhone and iPad can join as Receivers.';
}
