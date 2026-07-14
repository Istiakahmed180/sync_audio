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

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ConnectionService>(TcpConnectionService.new, fenix: true);
    Get.lazyPut<AudioCaptureService>(
      Platform.isAndroid
          ? AndroidSystemAudioCaptureService.new
          : PlaceholderAudioCaptureService.new,
      fenix: true,
    );
    Get.lazyPut<AudioPlaybackService>(
      Platform.isAndroid
          ? AndroidAudioTrackPlaybackService.new
          : PlaceholderAudioPlaybackService.new,
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
    Get.lazyPut<CalibrationStore>(AndroidCalibrationStore.new, fenix: true);
    Get.lazyPut<PairingStore>(AndroidPairingStore.new, fenix: true);
    Get.lazyPut<NativeAudioRuntime>(NativeAudioRuntime.new, fenix: true);
  }
}
