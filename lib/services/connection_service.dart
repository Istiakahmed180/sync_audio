import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/connection_status.dart';
import '../models/control_command.dart';
import '../models/receiver_session.dart';
import 'ip_address_service.dart';
import 'secure_transport.dart';

abstract class ConnectionService {
  Stream<String> get receivedMessages;

  Stream<ConnectionStatus> get statusChanges;

  Stream<ReceiverSession> get controlSessionChanges;

  Stream<ControlEvent> get controlEvents;

  Stream<String> get errors;

  ConnectionStatus get status;

  bool get isConnected;

  bool get isServerRunning;

  List<ReceiverSession> get controlSessions;

  Future<String?> startServer({required int port});

  Future<void> stopServer();

  Future<void> connect({required String ipAddress, required int port});

  Future<void> connectToReceivers({required List<ReceiverSession> receivers});

  Future<void> disconnect();

  Future<void> disconnectFrom(String receiverId);

  Future<void> sendMessage(String message);

  Future<void> sendMessageTo({
    required String receiverId,
    required String message,
  });

  Future<void> sendControlCommand({
    required String receiverId,
    required ControlCommand command,
  });

  void setPairingToken(String? token);

  void setPairingTokens(Map<String, String> tokens);
}

class TcpConnectionService implements ConnectionService {
  TcpConnectionService({IpAddressService? ipAddressService})
    : _ipAddressService = ipAddressService ?? IpAddressService();

  final IpAddressService _ipAddressService;
  final _receivedMessagesController = StreamController<String>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _sessionController = StreamController<ReceiverSession>.broadcast();
  final _controlEventController = StreamController<ControlEvent>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final Map<String, Socket> _sockets = <String, Socket>{};
  final Map<String, StreamSubscription<String>> _socketSubscriptions =
      <String, StreamSubscription<String>>{};
  final Map<String, ReceiverSession> _sessions = <String, ReceiverSession>{};
  final Map<String, _ControlTarget> _desiredReceivers =
      <String, _ControlTarget>{};
  final Map<String, Timer> _reconnectTimers = <String, Timer>{};
  final Set<String> _connecting = <String>{};
  final Set<String> _establishedConnections = <String>{};
  final Map<String, Timer> _pingTimers = <String, Timer>{};
  final Map<String, EncryptedControlChannel> _secureChannels =
      <String, EncryptedControlChannel>{};
  final Map<int, _PingRequest> _pendingPings = <int, _PingRequest>{};
  final Stopwatch _controlClock = Stopwatch()..start();
  final Map<String, Future<void>> _lineQueues = <String, Future<void>>{};
  final String _localSessionId =
      'sync-${DateTime.now().microsecondsSinceEpoch}';
  int _pingSequence = 0;
  String? _pairingToken;
  final Map<String, String> _pairingTokens = <String, String>{};

  ServerSocket? _server;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _serverRunning = false;

  @override
  Stream<String> get receivedMessages => _receivedMessagesController.stream;

  @override
  Stream<ConnectionStatus> get statusChanges => _statusController.stream;

  @override
  Stream<ReceiverSession> get controlSessionChanges =>
      _sessionController.stream;

  @override
  Stream<ControlEvent> get controlEvents => _controlEventController.stream;

  @override
  Stream<String> get errors => _errorsController.stream;

  @override
  ConnectionStatus get status => _status;

  @override
  bool get isConnected => _sockets.isNotEmpty;

  @override
  bool get isServerRunning => _serverRunning;

  @override
  List<ReceiverSession> get controlSessions =>
      List.unmodifiable(_sessions.values);

  @override
  Future<String?> startServer({required int port}) async {
    if (_serverRunning) {
      _emitError('The receiver server is already running.');
      return null;
    }
    _setStatus(ConnectionStatus.startingServer);
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverRunning = true;
      _server!.listen(
        _acceptClient,
        onError: _handleServerError,
        onDone: _handleServerDone,
      );
      _setStatus(ConnectionStatus.waiting);
      return _ipAddressService.findPrivateIpv4Address();
    } on SocketException catch (error) {
      _server = null;
      _emitError(
        _friendlySocketError(
          error,
          'Unable to start the receiver server',
          port,
        ),
      );
      _setStatus(ConnectionStatus.error);
      return null;
    }
  }

  void _acceptClient(Socket socket) {
    // A receiver server may accept more than one connection from the same
    // address (for example, loopback tests). Include the ephemeral port on
    // the server side so each accepted socket remains independently tracked.
    final id = '${socket.remoteAddress.address}:${socket.remotePort}';
    _registerSocket(id, socket, desired: false);
  }

  void _registerSocket(String id, Socket socket, {required bool desired}) {
    final oldSocket = _sockets[id];
    if (oldSocket != null && !identical(oldSocket, socket)) oldSocket.destroy();
    _sockets[id] = socket;
    if (desired) _establishedConnections.add(id);
    final existing = _sessions[id];
    final targetIpAddress = existing?.ipAddress ?? socket.remoteAddress.address;
    final targetPort = existing?.port ?? socket.remotePort;
    _updateSession(
      (existing ??
              ReceiverSession(
                id: id,
                ipAddress: targetIpAddress,
                port: targetPort,
              ))
          .copyWith(
            controlStatus: ControlConnectionStatus.connected,
            reconnectAttempt: 0,
          ),
    );
    _socketSubscriptions[id]?.cancel();
    _socketSubscriptions.remove(id);
    _socketSubscriptions[id] = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            _lineQueues[id] = (_lineQueues[id] ?? Future.value())
                .then((_) => _handleLine(id, line));
          },
          onError: (_) => _handleSocketClosed(id, socket),
          onDone: () => _handleSocketClosed(id, socket),
        );
    _setGlobalStatus(ConnectionStatus.connected);
    if (desired) {
      Timer.run(() {
        unawaited(
          _sendHello(
            receiverId: id,
            token: _pairingTokens[id] ?? _pairingToken,
          ).catchError((_) {
            _emitError('Handshake with receiver $id failed.');
            _handleSocketClosed(id, socket);
          }),
        );
      });
      _startPingTimer(id);
    }
  }

  @override
  Future<void> stopServer() async {
    _desiredReceivers.clear();
    _establishedConnections.clear();
    _cancelReconnectTimers();
    _cancelPingTimers();
    await _closeAllSockets();
    await _server?.close();
    _server = null;
    _serverRunning = false;
    _setStatus(ConnectionStatus.stopped);
  }

  @override
  Future<void> connect({required String ipAddress, required int port}) async {
    await connectToReceivers(
      receivers: [
        ReceiverSession(
          id: _sessionId(ipAddress, port),
          ipAddress: ipAddress,
          port: port,
        ),
      ],
    );
  }

  @override
  Future<void> connectToReceivers({
    required List<ReceiverSession> receivers,
  }) async {
    for (final receiver in receivers) {
      _desiredReceivers[receiver.id] = _ControlTarget(
        ipAddress: receiver.ipAddress,
        port: receiver.port,
      );
      _updateSession(
        receiver.copyWith(controlStatus: ControlConnectionStatus.connecting),
      );
    }
    await Future.wait(
      receivers.map((receiver) => _connectTarget(receiver.id)),
      eagerError: false,
    );
  }

  Future<void> _connectTarget(String id) async {
    final target = _desiredReceivers[id];
    if (target == null || _sockets.containsKey(id) || !_connecting.add(id)) {
      return;
    }
    final existing =
        _sessions[id] ??
        ReceiverSession(id: id, ipAddress: target.ipAddress, port: target.port);
    _updateSession(
      existing.copyWith(controlStatus: ControlConnectionStatus.connecting),
    );
    try {
      final socket = await Socket.connect(
        target.ipAddress,
        target.port,
        timeout: const Duration(seconds: 5),
      );
      if (_desiredReceivers.containsKey(id)) {
        _registerSocket(id, socket, desired: true);
      } else {
        socket.destroy();
      }
    } on SocketException {
      _emitError('Unable to connect to ${target.ipAddress}:${target.port}.');
      _updateSession(
        existing.copyWith(controlStatus: ControlConnectionStatus.error),
      );
      if (_establishedConnections.contains(id)) _scheduleReconnect(id);
    } on TimeoutException {
      _emitError('Connection to ${target.ipAddress} timed out.');
      _updateSession(
        existing.copyWith(controlStatus: ControlConnectionStatus.error),
      );
      if (_establishedConnections.contains(id)) _scheduleReconnect(id);
    } finally {
      _connecting.remove(id);
    }
  }

  void _scheduleReconnect(String id) {
    if (!_desiredReceivers.containsKey(id) ||
        _reconnectTimers.containsKey(id)) {
      return;
    }
    final current = _sessions[id];
    final attempt = (current?.reconnectAttempt ?? 0) + 1;
    final delaySeconds = 1 << (attempt.clamp(1, 5) - 1);
    _updateSession(
      (current ??
              ReceiverSession(
                id: id,
                ipAddress: _desiredReceivers[id]!.ipAddress,
                port: _desiredReceivers[id]!.port,
              ))
          .copyWith(
            controlStatus: ControlConnectionStatus.reconnecting,
            reconnectAttempt: attempt,
          ),
    );
    _reconnectTimers[id] = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimers.remove(id);
      unawaited(_connectTarget(id));
    });
  }

  @override
  Future<void> disconnectFrom(String receiverId) async {
    _desiredReceivers.remove(receiverId);
    _establishedConnections.remove(receiverId);
    _reconnectTimers.remove(receiverId)?.cancel();
    await _closeSocket(receiverId);
    final session = _sessions[receiverId];
    if (session != null) {
      _updateSession(
        session.copyWith(controlStatus: ControlConnectionStatus.disconnected),
      );
    }
    _setGlobalStatus(
      isConnected
          ? ConnectionStatus.connected
          : (_serverRunning
                ? ConnectionStatus.waiting
                : ConnectionStatus.disconnected),
    );
  }

  @override
  Future<void> disconnect() async {
    _desiredReceivers.clear();
    _establishedConnections.clear();
    _cancelReconnectTimers();
    _cancelPingTimers();
    await _closeAllSockets();
    for (final session in _sessions.values) {
      _emitSession(
        session.copyWith(controlStatus: ControlConnectionStatus.disconnected),
      );
    }
    _setGlobalStatus(
      _serverRunning ? ConnectionStatus.waiting : ConnectionStatus.disconnected,
    );
  }

  @override
  Future<void> sendMessage(String message) async {
    if (_sockets.isEmpty) {
      _emitError('Connect to at least one receiver before sending a message.');
      return;
    }
    for (final id in _sockets.keys.toList()) {
      await sendMessageTo(receiverId: id, message: message);
    }
  }

  @override
  Future<void> sendMessageTo({
    required String receiverId,
    required String message,
  }) async {
    final socket = _sockets[receiverId];
    if (socket == null) {
      _emitError('Receiver $receiverId is not connected.');
      return;
    }
    try {
      socket.write('${message.trim()}\n');
      await socket.flush();
    } on SocketException catch (error) {
      _emitError(
        _friendlySocketError(error, 'Unable to send the message', socket.remotePort),
      );
      await _handleSocketClosed(receiverId, socket);
    }
  }

  @override
  Future<void> sendControlCommand({
    required String receiverId,
    required ControlCommand command,
  }) async {
    final channel = _secureChannels[receiverId];
    await sendMessageTo(
      receiverId: receiverId,
      message: channel == null
          ? command.line
          : await channel.encrypt(command.line),
    );
  }

  Future<void> _handleLine(String sourceId, String line) async {
    if (line.startsWith('ENC:')) {
      final channel = _secureChannels[sourceId];
      if (channel == null) {
        _emitError('Encrypted control packet received before pairing.');
        return;
      }
      try {
        line = await channel.decrypt(line);
      } catch (_) {
        _emitError('Encrypted control packet rejected.');
        return;
      }
    }
    final command = ControlCommand.parse(line);
    // Control packets (PING/PONG, HELLO, stream commands, etc.) are internal
    // protocol traffic and must not replace the user's last test message.
    if (command == null && !_receivedMessagesController.isClosed) {
      _receivedMessagesController.add(line);
    }
    if (command == null) return;
    if (!_controlEventController.isClosed) {
      _controlEventController.add(
        ControlEvent(sourceId: sourceId, command: command),
      );
    }
    switch (command.type) {
      case ControlCommandType.hello:
        if (_pairingToken != null &&
            (command.arguments.length != 2 ||
                command.arguments[1] != _pairingToken)) {
          unawaited(
            sendMessageTo(
              receiverId: sourceId,
              message: const ControlCommand(
                type: ControlCommandType.error,
                arguments: ['PAIRING_REQUIRED', 'Pairing token rejected'],
              ).line,
            ),
          );
          unawaited(disconnectFrom(sourceId));
          return;
        }
        await sendMessageTo(
          receiverId: sourceId,
          message: ControlCommand(
            type: ControlCommandType.helloAck,
            arguments: [command.arguments.first],
          ).line,
        );
        if (command.arguments.length == 2 && _pairingToken != null) {
          await _establishSecureChannel(
            sourceId,
            _pairingToken!,
            command.arguments.first,
            'receiver',
          );
        }
      case ControlCommandType.ping:
        final receivedAt = _controlClock.elapsedMicroseconds;
        final sentAt = _controlClock.elapsedMicroseconds;
        unawaited(
          sendControlCommand(
            receiverId: sourceId,
            command: ControlCommand(
              type: ControlCommandType.pong,
              arguments: [command.arguments.first, '$receivedAt', '$sentAt'],
            ),
          ),
        );
      case ControlCommandType.pong:
        _handlePong(sourceId, command);
      case ControlCommandType.error:
        if (command.arguments.firstOrNull == 'PAIRING_REQUIRED') {
          _emitError(
            'Pairing rejected by receiver. Check the pairing code and connect again.',
          );
          await disconnectFrom(sourceId);
        }
      default:
        break;
    }
  }

  Future<void> _sendHello({
    required String receiverId,
    required String? token,
  }) async {
    await sendMessageTo(
      receiverId: receiverId,
      message: ControlCommand(
        type: ControlCommandType.hello,
        arguments: [_localSessionId, ?token],
      ).line,
    );
    if (token != null) {
      await _establishSecureChannel(receiverId, token, _localSessionId, 'host');
    }
  }

  Future<void> _establishSecureChannel(
    String id,
    String token,
    String sessionId,
    String role,
  ) async {
    final key = await SessionKeyService().derive(
      pairingToken: token,
      sessionId: sessionId,
    );
    _secureChannels[id] = EncryptedControlChannel(
      key: key,
      sessionId: sessionId,
      role: role,
    );
  }

  @override
  void setPairingToken(String? token) {
    _pairingToken = token?.trim().isEmpty == true ? null : token?.trim();
  }

  @override
  void setPairingTokens(Map<String, String> tokens) {
    _pairingTokens
      ..clear()
      ..addAll(tokens.map((key, value) => MapEntry(key, value.trim())));
  }

  void _evictStalePings() {
    if (_pendingPings.length < 256) return;
    final cutoff = _controlClock.elapsedMicroseconds - 10_000_000;
    _pendingPings.removeWhere((_, r) => r.sentAtMicros < cutoff);
  }

  void _handlePong(String sourceId, ControlCommand command) {
    final requestId = int.tryParse(command.arguments[0]);
    final receiverReceived = int.tryParse(command.arguments[1]);
    final receiverSent = int.tryParse(command.arguments[2]);
    final request = requestId == null ? null : _pendingPings.remove(requestId);
    if (request == null || receiverReceived == null || receiverSent == null) {
      return;
    }
    final hostReceived = _controlClock.elapsedMicroseconds;
    final session = _sessions[sourceId];
    if (session == null) return;
    _updateSession(
      session.copyWith(
        clockOffsetMicros:
            ((receiverReceived - request.sentAtMicros) +
                (receiverSent - hostReceived)) ~/
            2,
        roundTripTimeMicros:
            (hostReceived - request.sentAtMicros) -
            (receiverSent - receiverReceived),
        lastSyncMicros: hostReceived,
        controlStatus: ControlConnectionStatus.connected,
        reconnectAttempt: 0,
      ),
    );
  }

  void _startPingTimer(String id) {
    _pingTimers.remove(id)?.cancel();
    _pingTimers[id] = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sendPing(id),
    );
  }

  void _sendPing(String id) {
    if (!_sockets.containsKey(id)) return;
    final requestId = _pingSequence++;
    final sentAt = _controlClock.elapsedMicroseconds;
    _pendingPings[requestId] = _PingRequest(
      sessionId: id,
      sentAtMicros: sentAt,
    );
    _evictStalePings();
    unawaited(
      sendControlCommand(
        receiverId: id,
        command: ControlCommand(
          type: ControlCommandType.ping,
          arguments: ['$requestId', '$sentAt'],
        ),
      ),
    );
  }

  Future<void> _handleSocketClosed(String id, Socket socket) async {
    if (!identical(_sockets[id], socket)) return;
    await _socketSubscriptions.remove(id)?.cancel();
    _sockets.remove(id);
    socket.destroy();
    final session = _sessions[id];
    if (session != null) {
      _updateSession(
        session.copyWith(controlStatus: ControlConnectionStatus.disconnected),
      );
    }
    if (_desiredReceivers.containsKey(id) &&
        _establishedConnections.contains(id)) {
      _scheduleReconnect(id);
    }
    _setGlobalStatus(
      isConnected
          ? ConnectionStatus.connected
          : (_serverRunning
                ? ConnectionStatus.waiting
                : ConnectionStatus.disconnected),
    );
  }

  Future<void> _closeSocket(String id) async {
    _lineQueues.remove(id);
    await _socketSubscriptions.remove(id)?.cancel();
    _sockets.remove(id)?.destroy();
    _secureChannels.remove(id);
    _pingTimers.remove(id)?.cancel();
  }

  Future<void> _closeAllSockets() async {
    for (final id in _sockets.keys.toList()) {
      await _closeSocket(id);
    }
  }

  void _cancelReconnectTimers() {
    for (final timer in _reconnectTimers.values) {
      timer.cancel();
    }
    _reconnectTimers.clear();
  }

  void _cancelPingTimers() {
    for (final timer in _pingTimers.values) {
      timer.cancel();
    }
    _pingTimers.clear();
    _pendingPings.clear();
  }

  void _handleServerError(Object error) =>
      _emitError('The receiver server encountered a socket error.');

  void _handleServerDone() {
    _serverRunning = false;
    if (_status != ConnectionStatus.stopped) {
      _setStatus(ConnectionStatus.stopped);
    }
  }

  void _updateSession(ReceiverSession session) {
    _sessions[session.id] = session;
    _emitSession(session);
  }

  void _emitSession(ReceiverSession session) {
    if (!_sessionController.isClosed) _sessionController.add(session);
  }

  void _setGlobalStatus(ConnectionStatus value) {
    if (_sockets.isNotEmpty) {
      _setStatus(ConnectionStatus.connected);
    } else {
      _setStatus(value);
    }
  }

  void _setStatus(ConnectionStatus value) {
    _status = value;
    if (!_statusController.isClosed) _statusController.add(value);
  }

  void _emitError(String message) {
    if (!_errorsController.isClosed) _errorsController.add(message);
  }

  String _sessionId(String ipAddress, int port) => '$ipAddress:$port';

  String _friendlySocketError(
    SocketException error,
    String fallback,
    int port,
  ) {
    if (error.osError?.errorCode == 111 ||
        error.message.toLowerCase().contains('refused')) {
      return 'Connection refused on port $port.';
    }
    if (error.osError?.errorCode == 98 ||
        error.message.toLowerCase().contains('address already in use')) {
      return 'Port $port is already in use.';
    }
    return '$fallback. Check the IP address, port, and Wi-Fi connection.';
  }

  Future<void> dispose() async {
    await stopServer();
    await _receivedMessagesController.close();
    await _statusController.close();
    await _sessionController.close();
    await _controlEventController.close();
    await _errorsController.close();
  }
}

class _ControlTarget {
  const _ControlTarget({required this.ipAddress, required this.port});

  final String ipAddress;
  final int port;
}

class _PingRequest {
  const _PingRequest({required this.sessionId, required this.sentAtMicros});

  final String sessionId;
  final int sentAtMicros;
}
