import 'package:flutter/services.dart';

import 'audio_codec.dart';
import 'latency_metrics.dart';

class NativeAudioRuntime {
  static const _channel = MethodChannel('sync_audio/native_audio');

  Future<void> startNativeHostStream({
    required List<String> destinations,
    required int port,
    required AudioCodecType codec,
    required bool encrypted,
    required LatencyMode latencyMode,
    required String sessionId,
    String? pairingToken,
  }) {
    final arguments = <String, Object>{
      'destinations': destinations,
      'port': port,
      'codec': codec.name,
      'encrypted': encrypted,
      'latencyMode': latencyMode.name,
      'sessionId': sessionId,
    };
    if (pairingToken != null) arguments['pairingToken'] = pairingToken;
    return _channel.invokeMethod<void>('startNativeHostStream', arguments);
  }

  Future<void> stopNativeHostStream() async {
    try {
      await _channel.invokeMethod<void>('stopNativeHostStream');
    } on MissingPluginException {
      // Flutter unit tests and non-Android fallback platforms have no native channel.
    }
  }

  Future<void> addNativeHostReceivers(List<String> destinations) {
    return _channel.invokeMethod<void>(
      'addNativeHostReceivers',
      <String, Object>{'destinations': destinations},
    );
  }

  Future<void> startNativeReceiver({
    required int port,
    required LatencyMode latencyMode,
    required AudioCodecType codec,
    String? sessionId,
    String? pairingToken,
  }) {
    final arguments = <String, Object>{
      'port': port,
      'latencyMode': latencyMode.name,
      'codec': codec.name,
    };
    if (sessionId != null) arguments['sessionId'] = sessionId;
    if (pairingToken != null) arguments['pairingToken'] = pairingToken;
    return _channel.invokeMethod<void>('startNativeReceiver', arguments);
  }

  Future<void> stopNativeReceiver() async {
    try {
      await _channel.invokeMethod<void>('stopNativeReceiver');
    } on MissingPluginException {
      // Flutter unit tests and non-Android fallback platforms have no native channel.
    }
  }

  Future<Map<String, Object>> diagnostics() async {
    Map<String, Object>? result;
    try {
      result = await _channel.invokeMapMethod<String, Object>(
        'getNativeDiagnostics',
      );
    } on MissingPluginException {
      result = null;
    }
    return result ?? <String, Object>{'path': 'dart_fallback'};
  }
}
