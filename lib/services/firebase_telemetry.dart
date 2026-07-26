import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Firebase setup is intentionally best-effort so desktop builds without a
/// Firebase plugin implementation can still run normally.
class FirebaseTelemetry {
  FirebaseTelemetry._();

  static FirebaseAnalytics? _analytics;
  static bool _crashlyticsAvailable = false;

  static Future<void> initialize() async {
    if (!_supportsFirebaseCore) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _analytics = FirebaseAnalytics.instance;
      if (_supportsCrashlytics) {
        _crashlyticsAvailable = true;
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
          !kDebugMode,
        );
      }
      await logEvent('app_open');
    } catch (error, stack) {
      debugPrint('Firebase initialization skipped: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  static Future<void> logEvent(
    String name, [
    Map<String, Object?> parameters = const <String, Object?>{},
  ]) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      final safeParameters = <String, Object>{};
      for (final entry in parameters.entries) {
        final value = entry.value;
        if (value is num || value is String) {
          safeParameters[entry.key] = value as Object;
        } else if (value != null) {
          safeParameters[entry.key] = value.toString();
        }
      }
      await analytics.logEvent(name: name, parameters: safeParameters);
    } catch (_) {
      // Telemetry must never interrupt audio or pairing flows.
    }
  }

  static Future<void> recordError(
    Object error,
    StackTrace stack, {
    String reason = 'uncaught_error',
  }) async {
    if (!_crashlyticsAvailable) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stack,
        reason: reason,
        fatal: false,
      );
    } catch (_) {
      // Best effort only.
    }
  }

  /// Deliberately crashes a debug build so Firebase Crashlytics setup can be
  /// verified from a real device. This is never enabled in release builds.
  static Future<void> triggerTestCrash() async {
    if (!kDebugMode || !_crashlyticsAvailable) return;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    FirebaseCrashlytics.instance.crash();
  }

  static bool get _supportsFirebaseCore =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  static bool get _supportsCrashlytics =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
}
