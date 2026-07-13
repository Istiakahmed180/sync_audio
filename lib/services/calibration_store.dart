import 'package:flutter/services.dart';

abstract class CalibrationStore {
  Future<int?> read(String receiverId);

  Future<void> write(String receiverId, int calibrationMicros);
}

class AndroidCalibrationStore implements CalibrationStore {
  static const _channel = MethodChannel('sync_audio/calibration');

  @override
  Future<int?> read(String receiverId) async {
    try {
      return await _channel.invokeMethod<int>('read', receiverId);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> write(String receiverId, int calibrationMicros) async {
    try {
      await _channel.invokeMethod<void>('write', <String, Object>{
        'receiverId': receiverId,
        'calibrationMicros': calibrationMicros,
      });
    } on MissingPluginException {
      // Non-Android test and desktop builds have no native preference store.
    }
  }
}
