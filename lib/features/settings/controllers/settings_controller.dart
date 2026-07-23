import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../services/paired_device_store.dart';
import '../../../services/scheduled_streaming_service.dart';

class SettingsController extends GetxController {
  static const _deviceInfoChannel = MethodChannel('sync_audio/device_info');
  final themeMode = ThemeMode.system.obs;
  final isScheduledEnabled = false.obs;
  final scheduleStartHour = 8.obs;
  final scheduleStartMinute = 0.obs;
  final scheduleStopHour = 22.obs;
  final scheduleStopMinute = 0.obs;
  final totalStreamTimeMinutes = 0.obs;
  final totalDataSentMb = 0.0.obs;
  final totalPacketsLost = 0.obs;
  final platformName = 'Android'.obs;
  final deviceManufacturer = 'Unknown'.obs;
  final deviceModel = 'Unknown'.obs;
  final osVersion = 'Unknown'.obs;
  final osBuild = 'Unknown'.obs;
  final trustedDevices = <PairedDevice>[].obs;
  final _pairedDeviceStore = PairedDeviceStore();

  @override
  void onInit() {
    super.onInit();
    _applyPlatformFallback();
    _load();
    _loadDeviceInfo();
    unawaited(loadTrustedDevices());
  }

  void _applyPlatformFallback() {
    if (kIsWeb) {
      platformName.value = 'Web';
      deviceManufacturer.value = 'Browser';
      deviceModel.value = 'Web browser';
      osVersion.value = 'Web platform';
      osBuild.value = 'Browser';
      return;
    }
    platformName.value = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iOS',
      TargetPlatform.macOS => 'macOS',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.android => 'Android',
      TargetPlatform.fuchsia => 'Fuchsia',
    };
    deviceManufacturer.value = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => 'Apple',
      TargetPlatform.windows => 'Microsoft',
      TargetPlatform.linux => 'Linux community',
      TargetPlatform.android => 'Android device',
      TargetPlatform.fuchsia => 'Google',
    };
    deviceModel.value = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iPhone/iPad',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows PC',
      TargetPlatform.linux => 'Linux PC',
      TargetPlatform.android => 'Android device',
      TargetPlatform.fuchsia => 'Fuchsia device',
    };
    osVersion.value = platformName.value;
    osBuild.value = 'Unknown';
  }

  Future<void> loadTrustedDevices() async {
    trustedDevices.value = await _pairedDeviceStore.loadPaired();
  }

  Future<void> revokeTrustedDevice(String ipAddress) async {
    await _pairedDeviceStore.removePair(ipAddress);
    await loadTrustedDevices();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final info = await _deviceInfoChannel.invokeMapMethod<String, Object>(
        'getDeviceInfo',
      );
      if (info == null) return;
      platformName.value = '${info['platform'] ?? platformName.value}';
      deviceManufacturer.value = '${info['manufacturer'] ?? 'Unknown'}';
      deviceModel.value = '${info['model'] ?? 'Unknown'}';
      osVersion.value =
          '${info['osVersion'] ?? info['androidVersion'] ?? 'Unknown'}';
      osBuild.value = '${info['build'] ?? info['sdk'] ?? 'Unknown'}';
    } on MissingPluginException {
      // Keep platform-neutral fallback values.
    } catch (_) {
      // Device information is cosmetic.
    }
  }

  String get osVersionLabel =>
      platformName.value == 'Android' ? 'Android version' : 'OS version';

  String get osBuildLabel => platformName.value == 'Android' ? 'SDK' : 'Build';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode') ?? 'system';
    themeMode.value = switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    isScheduledEnabled.value = prefs.getBool('scheduled_enabled') ?? false;
    scheduleStartHour.value = prefs.getInt('sched_start_hour') ?? 8;
    scheduleStartMinute.value = prefs.getInt('sched_start_min') ?? 0;
    scheduleStopHour.value = prefs.getInt('sched_stop_hour') ?? 22;
    scheduleStopMinute.value = prefs.getInt('sched_stop_min') ?? 0;
    totalStreamTimeMinutes.value = prefs.getInt('total_stream_min') ?? 0;
    totalDataSentMb.value = prefs.getDouble('total_data_mb') ?? 0;
    totalPacketsLost.value = prefs.getInt('total_packets_lost') ?? 0;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    Get.changeThemeMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }

  Future<void> setScheduleEnabled(bool value) async {
    isScheduledEnabled.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('scheduled_enabled', value);
    await _refreshSchedule();
  }

  Future<void> scheduleStartTime(int hour, int minute) async {
    scheduleStartHour.value = hour;
    scheduleStartMinute.value = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sched_start_hour', hour);
    await prefs.setInt('sched_start_min', minute);
    await _refreshSchedule();
  }

  Future<void> scheduleStopTime(int hour, int minute) async {
    scheduleStopHour.value = hour;
    scheduleStopMinute.value = minute;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sched_stop_hour', hour);
    await prefs.setInt('sched_stop_min', minute);
    await _refreshSchedule();
  }

  Future<void> _refreshSchedule() async {
    if (Get.isRegistered<ScheduledStreamingService>()) {
      await Get.find<ScheduledStreamingService>().checkNow();
    }
  }

  void addStreamStats(int minutes, double dataMb, int lostPackets) {
    totalStreamTimeMinutes.value += minutes;
    totalDataSentMb.value += dataMb;
    totalPacketsLost.value += lostPackets;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('total_stream_min', totalStreamTimeMinutes.value);
      await prefs.setDouble('total_data_mb', totalDataSentMb.value);
      await prefs.setInt('total_packets_lost', totalPacketsLost.value);
    });
  }
}
