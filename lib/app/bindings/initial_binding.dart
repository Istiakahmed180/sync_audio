import 'package:get/get.dart';

import '../../services/audio_capture_service.dart';
import '../../services/audio_playback_service.dart';
import '../../services/connection_service.dart';
import '../../services/device_discovery_service.dart';
import '../../services/synchronization_service.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ConnectionService>(TcpConnectionService.new, fenix: true);
    Get.lazyPut<AudioCaptureService>(
      PlaceholderAudioCaptureService.new,
      fenix: true,
    );
    Get.lazyPut<AudioPlaybackService>(
      PlaceholderAudioPlaybackService.new,
      fenix: true,
    );
    Get.lazyPut<DeviceDiscoveryService>(
      PlaceholderDeviceDiscoveryService.new,
      fenix: true,
    );
    Get.lazyPut<SynchronizationService>(
      PlaceholderSynchronizationService.new,
      fenix: true,
    );
  }
}
