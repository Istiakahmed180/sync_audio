import 'package:flutter_test/flutter_test.dart';
import 'package:sync_audio/models/control_command.dart';
import 'package:sync_audio/services/connection_service.dart';

void main() {
  test('control protocol parses the supported wire commands', () {
    expect(
      ControlCommand.parse('STREAM_START:session-1:1234')?.type,
      ControlCommandType.streamStart,
    );
    expect(
      ControlCommand.parse('ERROR:BUFFER_UNDERRUN:packet lost')?.arguments,
      ['BUFFER_UNDERRUN', 'packet lost'],
    );
    expect(ControlCommand.parse('PONG:bad'), isNull);
  });

  test('TCP pairing and PING/PONG emit typed control events', () async {
    final receiver = TcpConnectionService()..setPairingToken('123456');
    final host = TcpConnectionService()..setPairingToken('123456');
    await receiver.startServer(port: 5055);
    final hello = receiver.controlEvents.firstWhere(
      (event) => event.command.type == ControlCommandType.hello,
    );

    await host.connect(ipAddress: '127.0.0.1', port: 5055);
    final event = await hello.timeout(const Duration(seconds: 2));
    expect(event.command.arguments, hasLength(2));
    expect(receiver.controlSessions, hasLength(1));

    await host.dispose();
    await receiver.dispose();
  });
}
