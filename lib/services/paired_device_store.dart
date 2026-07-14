import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PairedDevice {
  final String ipAddress;
  final int port;
  final String name;
  final DateTime lastConnected;

  const PairedDevice({
    required this.ipAddress,
    required this.port,
    required this.name,
    required this.lastConnected,
  });

  Map<String, dynamic> toJson() => {
    'ipAddress': ipAddress,
    'port': port,
    'name': name,
    'lastConnected': lastConnected.toIso8601String(),
  };

  factory PairedDevice.fromJson(Map<String, dynamic> json) => PairedDevice(
    ipAddress: json['ipAddress'] as String,
    port: json['port'] as int,
    name: json['name'] as String,
    lastConnected: DateTime.parse(json['lastConnected'] as String),
  );
}

class DeviceGroup {
  final String name;
  final List<String> deviceIps;

  const DeviceGroup({required this.name, required this.deviceIps});

  Map<String, dynamic> toJson() => {'name': name, 'deviceIps': deviceIps};

  factory DeviceGroup.fromJson(Map<String, dynamic> json) => DeviceGroup(
    name: json['name'] as String,
    deviceIps: List<String>.from(json['deviceIps'] as List),
  );
}

class PairedDeviceStore {
  static const _pairedKey = 'paired_devices';
  static const _groupsKey = 'device_groups';

  Future<List<PairedDevice>> loadPaired() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_pairedKey);
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list.map((e) => PairedDevice.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePair({required String ip, required int port, required String name}) async {
    final devices = await loadPaired();
    devices.removeWhere((d) => d.ipAddress == ip);
    devices.insert(0, PairedDevice(ipAddress: ip, port: port, name: name, lastConnected: DateTime.now()));
    if (devices.length > 20) devices.removeRange(20, devices.length);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairedKey, jsonEncode(devices.map((d) => d.toJson()).toList()));
  }

  Future<void> removePair(String ip) async {
    final devices = await loadPaired();
    devices.removeWhere((d) => d.ipAddress == ip);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pairedKey, jsonEncode(devices.map((d) => d.toJson()).toList()));
  }

  Future<List<DeviceGroup>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_groupsKey);
    if (data == null) return [];
    try {
      final list = jsonDecode(data) as List;
      return list.map((e) => DeviceGroup.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGroup(DeviceGroup group) async {
    final groups = await loadGroups();
    groups.removeWhere((g) => g.name == group.name);
    groups.add(group);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupsKey, jsonEncode(groups.map((g) => g.toJson()).toList()));
  }

  Future<void> removeGroup(String name) async {
    final groups = await loadGroups();
    groups.removeWhere((g) => g.name == name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_groupsKey, jsonEncode(groups.map((g) => g.toJson()).toList()));
  }
}
