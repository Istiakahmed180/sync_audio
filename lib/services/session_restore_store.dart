import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class RestoredReceiver {
  const RestoredReceiver({
    required this.ipAddress,
    required this.port,
    required this.pairingCode,
  });

  final String ipAddress;
  final int port;
  final String pairingCode;

  Map<String, Object> toJson() => {
    'ipAddress': ipAddress,
    'port': port,
    'pairingCode': pairingCode,
  };

  factory RestoredReceiver.fromJson(Map<String, dynamic> json) =>
      RestoredReceiver(
        ipAddress: json['ipAddress'] as String,
        port: json['port'] as int,
        pairingCode: json['pairingCode'] as String,
      );
}

class HostSessionSnapshot {
  const HostSessionSnapshot({
    required this.receivers,
    required this.audioPort,
    required this.codec,
    required this.latencyMode,
    required this.adaptiveJitter,
    required this.driftCorrection,
    required this.maximumDriftCorrectionPpm,
  });

  final List<RestoredReceiver> receivers;
  final int audioPort;
  final String codec;
  final String latencyMode;
  final bool adaptiveJitter;
  final bool driftCorrection;
  final int maximumDriftCorrectionPpm;

  Map<String, Object> toJson() => {
    'receivers': receivers.map((receiver) => receiver.toJson()).toList(),
    'audioPort': audioPort,
    'codec': codec,
    'latencyMode': latencyMode,
    'adaptiveJitter': adaptiveJitter,
    'driftCorrection': driftCorrection,
    'maximumDriftCorrectionPpm': maximumDriftCorrectionPpm,
  };

  factory HostSessionSnapshot.fromJson(
    Map<String, dynamic> json,
  ) => HostSessionSnapshot(
    receivers: (json['receivers'] as List)
        .map(
          (item) =>
              RestoredReceiver.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(growable: false),
    audioPort: json['audioPort'] as int,
    codec: json['codec'] as String,
    latencyMode: json['latencyMode'] as String,
    adaptiveJitter: json['adaptiveJitter'] as bool,
    driftCorrection: json['driftCorrection'] as bool,
    maximumDriftCorrectionPpm: json['maximumDriftCorrectionPpm'] as int,
  );
}

class SessionRestoreStore {
  static const _hostKey = 'sync_audio_last_host_session';
  static const _receiverServerKey = 'sync_audio_receiver_server_running';

  Future<void> saveHostSession(HostSessionSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKey, jsonEncode(snapshot.toJson()));
  }

  Future<HostSessionSnapshot?> loadHostSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_hostKey);
    if (raw == null) return null;
    try {
      return HostSessionSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setReceiverServerRunning(bool running) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_receiverServerKey, running);
  }

  Future<bool> shouldRestoreReceiverServer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_receiverServerKey) ?? false;
  }
}
