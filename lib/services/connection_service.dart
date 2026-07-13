import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/connection_status.dart';
import '../models/receiver_session.dart';
import 'ip_address_service.dart';

abstract class ConnectionService {
  Stream<String> get receivedMessages;

  Stream<ConnectionStatus> get statusChanges;

  Stream<ReceiverSession> get controlSessionChanges;

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
}

class TcpConnectionService implements ConnectionService {
  TcpConnectionService({IpAddressService? ipAddressService})
    : _ipAddressService = ipAddressService ?? IpAddressService();

  final IpAddressService _ipAddressService;
  final _receivedMessagesController = StreamController<String>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _sessionController = StreamController<ReceiverSession>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final Map<String, Socket> _sockets = <String, Socket>{};
  final Map<String, StreamSubscription<String>> _socketSubscriptions =
      <String, StreamSubscription<String>>{};
  final Map<String, ReceiverSession> _sessions = <String, ReceiverSession>{};
  final Map<String, _ControlTarget> _desiredReceivers =
      <String, _ControlTarget>{};
  final Map<String, Timer> _reconnectTimers = <String, Timer>{};
  final Set<String> _connecting = <String>{};

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
    _socketSubscriptions[id] = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _receivedMessagesController.add,
          onError: (_) => _handleSocketClosed(id, socket),
          onDone: () => _handleSocketClosed(id, socket),
        );
    _setGlobalStatus(ConnectionStatus.connected);
  }

  @override
  Future<void> stopServer() async {
    _desiredReceivers.clear();
    _cancelReconnectTimers();
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
    await Future.wait(receivers.map((receiver) => _connectTarget(receiver.id)));
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
      _scheduleReconnect(id);
    } on TimeoutException {
      _emitError('Connection to ${target.ipAddress} timed out.');
      _updateSession(
        existing.copyWith(controlStatus: ControlConnectionStatus.error),
      );
      _scheduleReconnect(id);
    } finally {
      _connecting.remove(id);
      _setGlobalStatus(ConnectionStatus.error);
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
    _cancelReconnectTimers();
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
        _friendlySocketError(error, 'Unable to send the message', socket.port),
      );
      await _handleSocketClosed(receiverId, socket);
    }
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
    if (_desiredReceivers.containsKey(id)) _scheduleReconnect(id);
    _setGlobalStatus(
      isConnected
          ? ConnectionStatus.connected
          : (_serverRunning
                ? ConnectionStatus.waiting
                : ConnectionStatus.disconnected),
    );
  }

  Future<void> _closeSocket(String id) async {
    await _socketSubscriptions.remove(id)?.cancel();
    _sockets.remove(id)?.destroy();
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

  String _sessionId(String ipAddress, int port) => ipAddress;

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
    await _errorsController.close();
  }
}

class _ControlTarget {
  const _ControlTarget({required this.ipAddress, required this.port});

  final String ipAddress;
  final int port;
}
