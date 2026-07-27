import 'package:flutter/services.dart';

class DeviceInfoService {
  static const _channel = MethodChannel('sync_audio/device_info');

  Future<Map<String, Object>> read() async {
    try {
      final info = await _channel.invokeMapMethod<String, Object>(
        'getDeviceInfo',
      );
      return info == null
          ? const <String, Object>{}
          : Map<String, Object>.from(info);
    } on MissingPluginException {
      return const <String, Object>{};
    } on PlatformException {
      return const <String, Object>{};
    }
  }
}
