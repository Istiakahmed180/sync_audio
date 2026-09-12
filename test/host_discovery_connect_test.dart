import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncmesh_audio/features/host/controllers/host_controller.dart';
import 'package:syncmesh_audio/models/audio_device.dart';
import 'package:syncmesh_audio/models/receiver_session.dart';
import 'package:syncmesh_audio/services/connection_service.dart';
import 'package:syncmesh_audio/services/device_discovery_service.dart';

class MutableDiscoveryService implements DeviceDiscoveryService {
  List<AudioDevice> devices = const [];

  @override
  Future<List<AudioDevice>> discover({
    Duration timeout = const Duration(milliseconds: 900),
  }) async => devices;

  @override
  Future<void> startResponder({
    required String deviceId,
    required String deviceName,
    required int controlPort,
    required String pairingCode,
  }) async {}

  @override
  Future<void> stopResponder() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'discovery falls back to a remembered pairing code when the Receiver '
    'stops advertising it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final receiver = TcpConnectionService()..setPairingToken('12345678');
      addTearDown(receiver.dispose);
      await receiver.startServer(port: 5099);

      final discovery = MutableDiscoveryService()
        ..devices = const [
          AudioDevice(
            id: 'dev-1',
            name: 'Kitchen',
            ipAddress: '127.0.0.1',
            port: 5099,
            pairingCode: '12345678',
          ),
        ];
      final hostService = TcpConnectionService();
      addTearDown(hostService.dispose);
      final controller = HostController(
        connectionService: hostService,
        discoveryService: discovery,
      );
      controller.portController.text = '5099';
      addTearDown(controller.stopDiscoveryPolling);
      controller.startDiscoveryPolling(showBusyIndicator: false);

      await controller.discoverReceivers();
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(
        receiver.controlSessions.any(
          (s) => s.controlStatus == ControlConnectionStatus.connected,
        ),
        isTrue,
        reason: 'initial discovery should connect',
      );

      await controller.disconnectReceiver('127.0.0.1');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(hostService.isConnected, isFalse);

      // The Receiver no longer advertises its code, but the host remembered it.
      discovery.devices = const [
        AudioDevice(
          id: 'dev-1',
          name: 'Kitchen',
          ipAddress: '127.0.0.1',
          port: 5099,
        ),
      ];
      await controller.discoverReceivers();
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(
        receiver.controlSessions.any(
          (s) => s.controlStatus == ControlConnectionStatus.connected,
        ),
        isTrue,
        reason: 'remembered code should still connect the Receiver',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
