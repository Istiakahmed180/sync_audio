import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_audio/app/app.dart';
import 'package:sync_audio/models/connection_status.dart';
import 'package:sync_audio/models/control_command.dart';
import 'package:sync_audio/services/connection_service.dart';

/// Device-safe smoke test intended to run on every connected Android phone.
/// The matrix runner executes this on 2–3 devices; the TCP part verifies the
/// same network stack used by pairing without requiring a special test server.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android app and pairing stack are healthy', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_complete': true,
    });
    await tester.pumpWidget(const SyncAudioApp());
    await tester.pumpAndSettle();
    expect(find.text('Host Device'), findsOneWidget);
    expect(find.text('Receiver Device'), findsOneWidget);

    final port = 57000 + DateTime.now().millisecond;
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
    await hello.timeout(const Duration(seconds: 5));
    expect(receiver.status, ConnectionStatus.connected);
  });
}
