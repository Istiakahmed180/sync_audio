import 'dart:io' show Platform;

import 'package:get/get.dart';

import '../../services/audio_capture_service.dart';
import '../../services/audio_playback_service.dart';
import '../../services/udp_audio_service.dart';
import '../../services/connection_service.dart';
import '../../services/device_discovery_service.dart';
import '../../services/synchronization_service.dart';
import '../../services/calibration_store.dart';
import '../../services/pairing_store.dart';
import '../../services/native_audio_runtime.dart';
import '../../services/ios_audio_capture_service.dart';
import '../../services/ios_audio_playback_service.dart';
import '../../services/macos_audio_capture_service.dart';
import '../../services/macos_audio_playback_service.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ConnectionService>(TcpConnectionService.new, fenix: true);

    Get.lazyPut<AudioCaptureService>(
      _captureServiceFactory,
      fenix: true,
    );

    Get.lazyPut<AudioPlaybackService>(
      _playbackServiceFactory,
      fenix: true,
    );

    Get.lazyPut<AudioStreamService>(
      () => UdpAudioService(
        playbackService: Get.find<AudioPlaybackService>(),
        captureService: Get.find<AudioCaptureService>(),
      ),
      fenix: true,
    );

    Get.lazyPut<DeviceDiscoveryService>(
      UdpDeviceDiscoveryService.new,
      fenix: true,
    );

    Get.lazyPut<SynchronizationService>(
      PlaceholderSynchronizationService.new,
      fenix: true,
    );

    Get.lazyPut<CalibrationStore>(
      SharedPrefsCalibrationStore.new,
      fenix: true,
    );

    Get.lazyPut<PairingStore>(
      SharedPrefsPairingStore.new,
      fenix: true,
    );

    Get.lazyPut<NativeAudioRuntime>(NativeAudioRuntime.new, fenix: true);
  }

  static AudioCaptureService _captureServiceFactory() {
    if (Platform.isAndroid) return AndroidSystemAudioCaptureService();
    if (Platform.isIOS) return IosAudioCaptureService();
    if (Platform.isMacOS) return MacosAudioCaptureService();
    return PlaceholderAudioCaptureService();
  }

  static AudioPlaybackService _playbackServiceFactory() {
    if (Platform.isAndroid) return AndroidAudioTrackPlaybackService();
    if (Platform.isIOS) return IosAudioPlaybackService();
    if (Platform.isMacOS) return MacosAudioPlaybackService();
    return PlaceholderAudioPlaybackService();
  }
}
