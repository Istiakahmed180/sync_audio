import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/connection_activity.dart';

class ConnectionActivityStore {
  static const _key = 'connection_activity_log';
  static const maxEntries = 50;

  Future<List<ConnectionActivity>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const <String>[];
      return raw
          .map((value) {
            try {
              return ConnectionActivity.fromJson(
                jsonDecode(value) as Map<String, dynamic>,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<ConnectionActivity>()
          .toList(growable: false);
    } catch (_) {
      return const <ConnectionActivity>[];
    }
  }

  Future<void> save(List<ConnectionActivity> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _key,
      entries
          .take(maxEntries)
          .map((entry) => jsonEncode(entry.toJson()))
          .toList(growable: false),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
