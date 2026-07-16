import 'dart:async';

import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/host/controllers/host_controller.dart';
import '../models/audio_stream_status.dart';
import '../models/connection_status.dart';

class ScheduledStreamingService {
  Timer? _timer;
  bool _wasStreamingBySchedule = false;
  DateTime? _lastScheduledStart;

  static const _checkInterval = Duration(seconds: 30);

  Future<({bool enabled, int startH, int startM, int stopH, int stopM})?>
  _loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('scheduled_enabled') ?? false;
    if (!enabled) return null;
    final startH = prefs.getInt('sched_start_hour') ?? 8;
    final startM = prefs.getInt('sched_start_min') ?? 0;
    final stopH = prefs.getInt('sched_stop_hour') ?? 22;
    final stopM = prefs.getInt('sched_stop_min') ?? 0;
    return (
      enabled: enabled,
      startH: startH,
      startM: startM,
      stopH: stopH,
      stopM: stopM,
    );
  }

  bool _inWindow(int startH, int startM, int stopH, int stopM) {
    final now = DateTime.now();
    final current = now.hour * 60 + now.minute;
    final start = startH * 60 + startM;
    final stop = stopH * 60 + stopM;
    if (start == stop) return true;
    if (start < stop) return current >= start && current < stop;
    // Overnight window, for example 10:00 PM to 6:00 AM.
    return current >= start || current < stop;
  }

  void start() {
    _timer?.cancel();
    _wasStreamingBySchedule = false;
    unawaited(_checkAndApply());
    _timer = Timer.periodic(_checkInterval, (_) {
      unawaited(_checkAndApply());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _wasStreamingBySchedule = false;
  }

  Future<void> checkNow() => _checkAndApply();

  Future<void> _checkAndApply() async {
    try {
      final schedule = await _loadSchedule();
      if (schedule == null) {
        if (_wasStreamingBySchedule) {
          await _stopHostAudio();
          _wasStreamingBySchedule = false;
        }
        return;
      }

      final inWindow = _inWindow(
        schedule.startH,
        schedule.startM,
        schedule.stopH,
        schedule.stopM,
      );

      if (!Get.isRegistered<HostController>()) return;

      final host = Get.find<HostController>();
      if (!host.isConnected) return;

      final isStreaming = host.audioStatus.value == AudioStreamStatus.streaming;
      final isConnecting =
          host.connectionStatus.value == ConnectionStatus.connecting;

      if (inWindow && !isStreaming && !isConnecting) {
        if (_lastScheduledStart != null) {
          final elapsed = DateTime.now().difference(_lastScheduledStart!);
          if (elapsed < const Duration(minutes: 5)) return;
        }
        _lastScheduledStart = DateTime.now();
        await host.startSystemAudioStream();
        if (host.audioStatus.value == AudioStreamStatus.streaming) {
          _wasStreamingBySchedule = true;
        }
      } else if (!inWindow && isStreaming) {
        await host.stopSystemAudioStream();
        _wasStreamingBySchedule = false;
      }
    } catch (_) {
      // Scheduling is best-effort; never crash the app.
    }
  }

  Future<void> _stopHostAudio() async {
    try {
      if (!Get.isRegistered<HostController>()) return;
      final host = Get.find<HostController>();
      if (host.audioStatus.value == AudioStreamStatus.streaming) {
        await host.stopSystemAudioStream();
      }
    } catch (_) {}
  }
}
