import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_telemetry.dart';

/// Stores a small, privacy-filtered crash trail locally for support exports.
///
/// Remote crash backends can be added later without changing the app-wide
/// error hooks. Pairing codes, IP addresses, and other obvious secrets are
/// redacted before anything is persisted.
class CrashReporter {
  CrashReporter._();

  static const _storageKey = 'crash_reports_v1';
  static const _maxReports = 20;
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      record(
        details.exception,
        details.stack ?? StackTrace.current,
        source: 'flutter',
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, source: 'platform');
      return true;
    };
  }

  static Future<void> record(
    Object error,
    StackTrace stack, {
    String source = 'uncaught',
  }) async {
    await FirebaseTelemetry.recordError(error, stack, reason: source);
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_storageKey) ?? <String>[];
      final entry = <String, String>{
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'source': source,
        'error': _redact(error.toString()),
        'stack': _redact(stack.toString()),
      };
      final updated = <String>[jsonEncode(entry), ...existing];
      await prefs.setStringList(
        _storageKey,
        updated.take(_maxReports).toList(growable: false),
      );
    } catch (_) {
      // Error reporting must never become a second source of app failures.
    }
  }

  static Future<void> triggerTestCrash() {
    return FirebaseTelemetry.triggerTestCrash();
  }

  static Future<List<Map<String, Object>>> recentReports() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final reports = <Map<String, Object>>[];
      for (final raw in prefs.getStringList(_storageKey) ?? <String>[]) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          reports.add({
            for (final entry in decoded.entries)
              '${entry.key}': '${entry.value}',
          });
        }
      }
      return reports;
    } catch (_) {
      return const <Map<String, Object>>[];
    }
  }

  static String _redact(String value) {
    return value
        .replaceAll(RegExp(r'\b\d{6,8}\b'), '[REDACTED_CODE]')
        .replaceAll(RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'), '[REDACTED_IP]');
  }
}
