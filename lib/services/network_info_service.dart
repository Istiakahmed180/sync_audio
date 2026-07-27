import 'package:flutter/services.dart';

class NetworkInfoService {
  static const _channel = MethodChannel('sync_audio/network_info');

  Future<String?> connectedNetworkName() async {
    try {
      final name = await _channel.invokeMethod<String>('getNetworkName');
      final trimmed = name?.trim();
      if (trimmed == null || trimmed.isEmpty || _isUnknown(trimmed)) {
        return null;
      }
      return trimmed;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  bool _isUnknown(String value) {
    final normalized = value.toLowerCase();
    return normalized == '<unknown ssid>' ||
        normalized == 'unknown' ||
        normalized == 'not available';
  }
}
