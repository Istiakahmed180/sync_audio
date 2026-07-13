import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/connection_status.dart';
import 'ip_address_service.dart';

abstract class ConnectionService {
  Stream<String> get receivedMessages;
  Stream<ConnectionStatus> get statusChanges;
  Stream<String> get errors;
  ConnectionStatus get status;
  bool get isConnected;
  bool get isServerRunning;

  Future<String?> startServer({required int port});
  Future<void> stopServer();
  Future<void> connect({required String ipAddress, required int port});
  Future<void> disconnect();
  Future<void> sendMessage(String message);
}

class TcpConnectionService implements ConnectionService {
  TcpConnectionService({IpAddressService? ipAddressService})
    : _ipAddressService = ipAddressService ?? IpAddressService();

  final IpAddressService _ipAddressService;
  final _receivedMessagesController = StreamController<String>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _errorsController = StreamController<String>.broadcast();

  ServerSocket? _server;
  Socket? _socket;
  StreamSubscription<String>? _socketSubscription;
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _serverRunning = false;

  @override
  Stream<String> get receivedMessages => _receivedMessagesController.stream;

  @override
  Stream<ConnectionStatus> get statusChanges => _statusController.stream;

  @override
  Stream<String> get errors => _errorsController.stream;

  @override
  ConnectionStatus get status => _status;

  @override
  bool get isConnected => _socket != null;

  @override
  bool get isServerRunning => _serverRunning;

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
        _friendlySocketError(error, 'Unable to start the receiver server'),
      );
      _setStatus(ConnectionStatus.error);
      return null;
    }
  }

  void _acceptClient(Socket socket) {
    if (_socket != null) {
      socket.destroy();
      _emitError('Only one host connection is supported at a time.');
      return;
    }
    _socket = socket;
    _listenToSocket(socket);
    _setStatus(ConnectionStatus.connected);
  }

  @override
  Future<void> stopServer() async {
    await _closeSocket();
    await _server?.close();
    _server = null;
    _serverRunning = false;
    _setStatus(ConnectionStatus.stopped);
  }

  @override
  Future<void> connect({required String ipAddress, required int port}) async {
    if (isConnected) return;
    _setStatus(ConnectionStatus.connecting);
    try {
      final socket = await Socket.connect(
        ipAddress,
        port,
        timeout: const Duration(seconds: 5),
      );
      _socket = socket;
      _listenToSocket(socket);
      _setStatus(ConnectionStatus.connected);
    } on SocketException catch (error) {
      _socket = null;
      _emitError(
        _friendlySocketError(error, 'Unable to connect to the receiver'),
      );
      _setStatus(ConnectionStatus.error);
    } on TimeoutException {
      _emitError(
        'The connection timed out. Check the IP address and Wi-Fi network.',
      );
      _setStatus(ConnectionStatus.error);
    }
  }

  void _listenToSocket(Socket socket) {
    _socketSubscription = socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _receivedMessagesController.add,
          onError: _handleSocketError,
          onDone: _handleSocketDone,
        );
  }

  @override
  Future<void> sendMessage(String message) async {
    final socket = _socket;
    if (socket == null) {
      _emitError('Connect to a receiver before sending a message.');
      return;
    }
    try {
      socket.write('${message.trim()}\n');
      await socket.flush();
    } on SocketException catch (error) {
      _emitError(_friendlySocketError(error, 'Unable to send the message'));
      await _closeSocket();
    }
  }

  @override
  Future<void> disconnect() async {
    await _closeSocket();
    _setStatus(
      _serverRunning ? ConnectionStatus.waiting : ConnectionStatus.disconnected,
    );
  }

  Future<void> _closeSocket() async {
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    final socket = _socket;
    _socket = null;
    socket?.destroy();
  }

  void _handleSocketDone() {
    _socket = null;
    _socketSubscription = null;
    _setStatus(
      _serverRunning ? ConnectionStatus.waiting : ConnectionStatus.disconnected,
    );
  }

  void _handleSocketError(Object error) {
    _emitError('The connection was interrupted.');
    _handleSocketDone();
  }

  void _handleServerError(Object error) =>
      _emitError('The receiver server encountered a socket error.');

  void _handleServerDone() {
    _serverRunning = false;
    if (_status != ConnectionStatus.stopped) {
      _setStatus(ConnectionStatus.stopped);
    }
  }

  void _setStatus(ConnectionStatus value) {
    _status = value;
    if (!_statusController.isClosed) _statusController.add(value);
  }

  void _emitError(String message) {
    if (!_errorsController.isClosed) _errorsController.add(message);
  }

  String _friendlySocketError(SocketException error, String fallback) {
    if (error.osError?.errorCode == 111 ||
        error.message.toLowerCase().contains('refused')) {
      return 'Connection refused. Confirm the receiver server is running.';
    }
    if (error.osError?.errorCode == 98 ||
        error.message.toLowerCase().contains('address already in use')) {
      return 'Port 5050 is already in use.';
    }
    return '$fallback. Check the IP address, port, and Wi-Fi connection.';
  }

  Future<void> dispose() async {
    await stopServer();
    await _receivedMessagesController.close();
    await _statusController.close();
    await _errorsController.close();
  }
}
