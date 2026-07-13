import '../models/audio_device.dart';

abstract class DeviceDiscoveryService {
  Future<List<AudioDevice>> discover();
}

class PlaceholderDeviceDiscoveryService implements DeviceDiscoveryService {
  @override
  Future<List<AudioDevice>> discover() async => const [];
}
