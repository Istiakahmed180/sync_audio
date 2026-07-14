import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class CalibrationStore {
  Future<int?> read(String receiverId);

  Future<void> write(String receiverId, int calibrationMicros);
}

class SharedPrefsCalibrationStore implements CalibrationStore {
  static String _key(String receiverId) => 'sync_audio_cal_$receiverId';
  final Map<String, int> _inMemory = {};

  @override
  Future<int?> read(String receiverId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getInt(_key(receiverId));
      return value ?? _inMemory[receiverId];
    } catch (_) {
      return _inMemory[receiverId];
    }
  }

  @override
  Future<void> write(String receiverId, int calibrationMicros) async {
    _inMemory[receiverId] = calibrationMicros;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key(receiverId), calibrationMicros);
    } catch (_) {
      // Fallback: calibration stored in memory only.
    }
  }
}

class AndroidCalibrationStore implements CalibrationStore {
  static const _channel = MethodChannel('sync_audio/calibration');
  final SharedPrefsCalibrationStore _fallback = SharedPrefsCalibrationStore();

  @override
  Future<int?> read(String receiverId) async {
    try {
      final result = await _channel.invokeMethod<int>('read', receiverId);
      if (result != null) return result;
    } on MissingPluginException {
      // Native calibration store unavailable; fall back to SharedPreferences.
    }
    return _fallback.read(receiverId);
  }

  @override
  Future<void> write(String receiverId, int calibrationMicros) async {
    try {
      await _channel.invokeMethod<void>('write', <String, Object>{
        'receiverId': receiverId,
        'calibrationMicros': calibrationMicros,
      });
    } on MissingPluginException {
      await _fallback.write(receiverId, calibrationMicros);
    }
  }
}
