import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sync_audio/models/connection_status.dart';
import 'package:sync_audio/models/control_command.dart';
import 'package:sync_audio/services/connection_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real TCP pairing flow works on the device network stack', (
    tester,
  ) async {
    final port = 56000 + DateTime.now().millisecond;
    final receiver = TcpConnectionService()..setPairingToken('12345678');
    final host = TcpConnectionService()..setPairingToken('12345678');
    addTearDown(() async {
      await host.dispose();
      await receiver.dispose();
    });

    await receiver.startServer(port: port);
    final hello = receiver.controlEvents.firstWhere(
      (event) => event.command.type == ControlCommandType.hello,
    );
    await host.connect(ipAddress: '127.0.0.1', port: port);

    final event = await hello.timeout(const Duration(seconds: 3));
    expect(event.command.type, ControlCommandType.hello);
    expect(receiver.status, ConnectionStatus.connected);
    expect(receiver.controlSessions, hasLength(1));
  });
}
