import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_audio/features/host/controllers/host_controller.dart';
import 'package:sync_audio/features/receiver/controllers/receiver_controller.dart';
import 'package:sync_audio/models/connection_status.dart';
import 'package:sync_audio/models/control_command.dart';
import 'package:sync_audio/models/receiver_session.dart';
import 'package:sync_audio/services/connection_service.dart';

class FakeConnectionService implements ConnectionService {
  final _messages = StreamController<String>.broadcast();
  final _statuses = StreamController<ConnectionStatus>.broadcast();
  final _controlSessions = StreamController<ReceiverSession>.broadcast();
  final _controlEvents = StreamController<ControlEvent>.broadcast();
  final _errors = StreamController<String>.broadcast();
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _connected = false;
  bool _serverRunning = false;
  String? sentMessage;
  ControlCommand? sentCommand;
  final List<ReceiverSession> _sessions = [];
  String? pairingToken;

  @override
  Stream<String> get receivedMessages => _messages.stream;
  @override
  Stream<ConnectionStatus> get statusChanges => _statuses.stream;
  @override
  Stream<ReceiverSession> get controlSessionChanges => _controlSessions.stream;
  @override
  Stream<ControlEvent> get controlEvents => _controlEvents.stream;
  @override
  Stream<String> get errors => _errors.stream;
  @override
  ConnectionStatus get status => _status;
  @override
  bool get isConnected => _connected;
  @override
  bool get isServerRunning => _serverRunning;
  @override
  List<ReceiverSession> get controlSessions => List.unmodifiable(_sessions);

  void _emit(ConnectionStatus status) {
    _status = status;
    _statuses.add(status);
  }

  @override
  Future<String?> startServer({required int port}) async {
    _serverRunning = true;
    _emit(ConnectionStatus.waiting);
    return '192.168.1.20';
  }

  @override
  Future<void> stopServer() async {
    _serverRunning = false;
    _connected = false;
    _emit(ConnectionStatus.stopped);
  }

  @override
  Future<void> connect({required String ipAddress, required int port}) async {
    _emit(ConnectionStatus.connecting);
    _connected = true;
    _emit(ConnectionStatus.connected);
  }

  @override
  Future<void> connectToReceivers({
    required List<ReceiverSession> receivers,
  }) async {
    _sessions
      ..clear()
      ..addAll(
        receivers.map(
          (receiver) => receiver.copyWith(
            controlStatus: ControlConnectionStatus.connected,
          ),
        ),
      );
    for (final session in _sessions) {
      _controlSessions.add(session);
    }
    _connected = _sessions.isNotEmpty;
    _emit(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _emit(ConnectionStatus.disconnected);
  }

  @override
  Future<void> disconnectFrom(String receiverId) async {
    _sessions.removeWhere((session) => session.id == receiverId);
    _connected = _sessions.isNotEmpty;
  }

  @override
  Future<void> sendMessage(String message) async => sentMessage = message;

  @override
  Future<void> sendMessageTo({
    required String receiverId,
    required String message,
  }) async => sentMessage = message;

  @override
  Future<void> sendControlCommand({
    required String receiverId,
    required ControlCommand command,
  }) async {
    sentCommand = command;
    sentMessage = command.line;
  }

  @override
  void setPairingToken(String? token) => pairingToken = token;

  @override
  void setPairingTokens(Map<String, String> tokens) {}

  void emitMessage(String message) => _messages.add(message);

  Future<void> dispose() async {
    await _messages.close();
    await _statuses.close();
    await _controlSessions.close();
    await _controlEvents.close();
    await _errors.close();
  }
}

void main() {
  late FakeConnectionService service;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    service = FakeConnectionService();
  });
  tearDown(() => service.dispose());

  test('host validates empty IP, invalid IP, and invalid port', () async {
    final controller = HostController(connectionService: service);
    controller.onInit();

    await controller.connect();
    expect(controller.errorMessage.value, 'Enter the receiver IP address.');
    controller.receiverIpController.text = 'not-an-ip';
    await controller.connect();
    expect(controller.errorMessage.value, 'Enter a valid IPv4 address.');
    controller.receiverIpController.text = '192.168.1.20';
    controller.portController.text = '70000';
    await controller.connect();
    expect(controller.errorMessage.value, 'Invalid port configured.');
    controller.onClose();
  });

  test(
    'fake connection service simulates connection and received message',
    () async {
      final host = HostController(connectionService: service);
      final receiver = ReceiverController(connectionService: service);
      host.onInit();
      receiver.onInit();
      host.receiverIpController.text = '192.168.1.20';
      host.pairingTokenController.text = '12345678';

      await host.connect();
      await Future<void>.delayed(Duration.zero);
      expect(host.connectionStatus.value, ConnectionStatus.connected);
      expect(host.isConnected, isTrue);

      service.emitMessage('Hello Receiver');
      await Future<void>.delayed(Duration.zero);
      expect(receiver.lastReceivedMessage.value, 'Hello Receiver');

      host.testMessageController.text = 'Hello Receiver';
      await host.sendTestMessage();
      expect(service.sentMessage, 'Hello Receiver');
      host.onClose();
      receiver.onClose();
    },
  );

  test('receiver start and stop update server state', () async {
    final controller = ReceiverController(connectionService: service);
    controller.onInit();
    await controller.startServer();
    expect(controller.isServerRunning.value, isTrue);
    expect(controller.localIpAddress.value, '192.168.1.20');
    await controller.stopServer();
    expect(controller.isServerRunning.value, isFalse);
    expect(controller.connectionStatus.value, ConnectionStatus.stopped);
    controller.onClose();
  });

  test(
    'line-delimited messages are represented as individual messages',
    () async {
      final controller = ReceiverController(connectionService: service);
      controller.onInit();
      service.emitMessage('first line');
      await Future<void>.delayed(Duration.zero);
      expect(controller.lastReceivedMessage.value, 'first line');
      service.emitMessage('second line');
      await Future<void>.delayed(Duration.zero);
      expect(controller.lastReceivedMessage.value, 'second line');
      controller.onClose();
    },
  );

  test(
    'TCP service receives line-delimited text without physical devices',
    () async {
      final receiver = TcpConnectionService();
      final host = TcpConnectionService();
      await receiver.startServer(port: 5051);
      final received = receiver.receivedMessages.first;

      await host.connect(
        ipAddress: InternetAddress.loopbackIPv4.address,
        port: 5051,
      );
      await host.sendMessage('Hello Receiver');

      expect(await received, 'Hello Receiver');
      await host.dispose();
      await receiver.dispose();
    },
  );
}
