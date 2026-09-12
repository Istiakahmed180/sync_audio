import 'package:flutter_test/flutter_test.dart';
import 'package:syncmesh_audio/models/control_command.dart';
import 'package:syncmesh_audio/models/receiver_session.dart';
import 'package:syncmesh_audio/services/connection_service.dart';

void main() {
  test(
    'concurrent control writes on one socket keep the connection alive',
    () async {
      final receiver = TcpConnectionService()..setPairingToken('12345678');
      final host = TcpConnectionService()..setPairingToken('12345678');
      addTearDown(() async {
        await host.dispose();
        await receiver.dispose();
      });

      await receiver.startServer(port: 59123);
      await host.connectToReceivers(
        receivers: [
          ReceiverSession(id: '127.0.0.1', ipAddress: '127.0.0.1', port: 59123),
        ],
      );

      // HELLO_ACK, RECEIVER_READY and stream commands are sent from different
      // call sites and can overlap on the same socket. Before writes were
      // serialized per socket, a write during an in-flight flush threw
      // "StreamSink is bound to a stream" and tore the connection down.
      await Future.wait([
        for (var index = 0; index < 60; index++)
          host.sendControlCommand(
            receiverId: '127.0.0.1',
            command: ControlCommand(
              type: ControlCommandType.ping,
              arguments: ['$index', '0', '0'],
            ),
          ),
      ]);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(host.isConnected, isTrue);
      expect(
        receiver.controlSessions
            .where(
              (session) =>
                  session.controlStatus == ControlConnectionStatus.connected,
            )
            .length,
        1,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
