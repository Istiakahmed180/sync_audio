import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PairedDevice {
  final String ipAddress;
  final int port;
  final String name;
  final String? deviceId;
  final DateTime lastConnected;

  const PairedDevice({
    required this.ipAddress,
    required this.port,
    required this.name,
    this.deviceId,
    required this.lastConnected,
  });

  Map<String, dynamic> toJson() => {
    'ipAddress': ipAddress,
    'port': port,
    'name': name,
    if (deviceId != null && deviceId!.isNotEmpty) 'deviceId': deviceId,
    'lastConnected': lastConnected.toIso8601String(),
  };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
    ipAddress: json['ipAddress'] as String,
    port: json['port'] as int,
    name: json['name'] as String,
    deviceId: (json['deviceId'] as String?)?.trim(),
    lastConnected: DateTime.parse(json['lastConnected'] as String),
  );
}

class DeviceGroup {
  final String name;
  final List<String> deviceIps;
  final Map<String, String> pairingCodes;
  final Map<String, double> receiverVolumes;
  final Map<String, int> receiverCalibrations;
  final Map<String, String> deviceIds;
  final bool favorite;

  const DeviceGroup({
    required this.name,
    required this.deviceIps,
    this.pairingCodes = const <String, String>{},
    this.receiverVolumes = const <String, double>{},
    this.receiverCalibrations = const <String, int>{},
    this.deviceIds = const <String, String>{},
    this.favorite = false,
  });

  DeviceGroup copyWith({String? name, bool? favorite}) => DeviceGroup(
    name: name ?? this.name,
    deviceIps: deviceIps,
    pairingCodes: pairingCodes,
    receiverVolumes: receiverVolumes,
    receiverCalibrations: receiverCalibrations,
    deviceIds: deviceIds,
    favorite: favorite ?? this.favorite,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'deviceIps': deviceIps,
    'pairingCodes': pairingCodes,
    'receiverVolumes': receiverVolumes,
    'receiverCalibrations': receiverCalibrations,
    'deviceIds': deviceIds,
    'favorite': favorite,
  };

  factory DeviceGroup.fromJson(Map<String, dynamic> json) {
    final rawVolumes = json['receiverVolumes'] as Map?;
    final rawCalibrations = json['receiverCalibrations'] as Map?;
    final rawDeviceIds = json['deviceIds'] as Map?;
    return DeviceGroup(
      name: json['name'] as String,
      deviceIps: List<String>.from(json['deviceIps'] as List),
      pairingCodes: json['pairingCodes'] == null
          ? const <String, String>{}
          : Map<String, String>.from(json['pairingCodes'] as Map),
      receiverVolumes: rawVolumes == null
          ? const <String, double>{}
          : rawVolumes.map(
              (key, value) =>
                  MapEntry(key.toString(), (value as num).toDouble()),
            ),
      receiverCalibrations: rawCalibrations == null
          ? const <String, int>{}
          : rawCalibrations.map(
              (key, value) => MapEntry(key.toString(), (value as num).toInt()),
            ),
      deviceIds: rawDeviceIds == null
          ? const <String, String>{}
          : Map<String, String>.from(rawDeviceIds),
      favorite: json['favorite'] as bool? ?? false,
    );
  }
}

class PairedDeviceStore {
  static const _pairedKey = 'sync_audio_paired_devices';
  static const _groupsKey = 'sync_audio_device_groups';
  static const _legacyPairedKey = 'paired_devices';
  static const _legacyGroupsKey = 'device_groups';
  static const _storage = FlutterSecureStorage();

  Future<List<PairedDevice>> loadPaired() async {
    final data = await _readWithMigration(
      secureKey: _pairedKey,
      legacyKey: _legacyPairedKey,
    );
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list
          .map((e) => PairedDevice.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePair({
    required String ip,
    required int port,
    required String name,
    String? deviceId,
  }) async {
    final devices = await loadPaired();
    devices.removeWhere(
      (d) =>
          d.ipAddress == ip ||
          (deviceId != null && deviceId.isNotEmpty && d.deviceId == deviceId),
    );
    devices.insert(
      0,
      PairedDevice(
        ipAddress: ip,
        port: port,
        name: name,
        deviceId: deviceId,
        lastConnected: DateTime.now(),
      ),
    );
    if (devices.length > 20) devices.removeRange(20, devices.length);
    await _write(
      _pairedKey,
      jsonEncode(devices.map((d) => d.toJson()).toList()),
    );
  }

  Future<void> removePair(String ip) async {
    final devices = await loadPaired();
    devices.removeWhere((d) => d.ipAddress == ip);
    await _write(
      _pairedKey,
      jsonEncode(devices.map((d) => d.toJson()).toList()),
    );
  }

  Future<List<DeviceGroup>> loadGroups() async {
    final data = await _readWithMigration(
      secureKey: _groupsKey,
      legacyKey: _legacyGroupsKey,
    );
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list
          .map((e) => DeviceGroup.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGroup(DeviceGroup group) async {
    final groups = await loadGroups();
    groups.removeWhere((g) => g.name == group.name);
    groups.add(group);
    await _write(
      _groupsKey,
      jsonEncode(groups.map((g) => g.toJson()).toList()),
    );
  }

  Future<void> removeGroup(String name) async {
    final groups = await loadGroups();
    groups.removeWhere((g) => g.name == name);
    await _write(
      _groupsKey,
      jsonEncode(groups.map((g) => g.toJson()).toList()),
    );
  }

  Future<void> importGroups(List<DeviceGroup> imported) async {
    final groups = await loadGroups();
    for (final group in imported) {
      groups.removeWhere((existing) => existing.name == group.name);
      groups.add(group);
    }
    await _write(
      _groupsKey,
      jsonEncode(groups.map((group) => group.toJson()).toList()),
    );
  }

  Future<String?> _readWithMigration({
    required String secureKey,
    required String legacyKey,
  }) async {
    try {
      final secureValue = await _storage.read(key: secureKey);
      if (secureValue != null) return secureValue;
    } catch (_) {
      // Flutter tests and unsupported platforms may not have a secure-storage
      // plugin. Keep the legacy fallback for those environments only.
    }

    final prefs = await SharedPreferences.getInstance();
    // The secure key is also used as a local fallback in Flutter tests and on
    // platforms without a registered secure-storage implementation.
    final legacyValue =
        prefs.getString(legacyKey) ?? prefs.getString(secureKey);
    if (legacyValue == null) return null;

    try {
      await _storage.write(key: secureKey, value: legacyValue);
      await prefs.remove(legacyKey);
    } catch (_) {
      // Leave the legacy value in place if secure storage is unavailable.
    }
    return legacyValue;
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      // Keep unit tests and unsupported platforms functional.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }
}
