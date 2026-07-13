import 'dart:async';

import 'package:get/get.dart';

import '../../../models/connection_status.dart';
import '../../../services/connection_service.dart';

class ReceiverController extends GetxController {
  ReceiverController({ConnectionService? connectionService})
    : _service = connectionService ?? Get.find<ConnectionService>();

  static const defaultPort = 5050;
  final ConnectionService _service;
  final connectionStatus = ConnectionStatus.disconnected.obs;
  final localIpAddress = 'Not available'.obs;
  final isServerRunning = false.obs;
  final isConnectedToHost = false.obs;
  final lastReceivedMessage = ''.obs;
  final errorMessage = RxnString();
  late final StreamSubscription<String> _messageSubscription;
  late final StreamSubscription<ConnectionStatus> _statusSubscription;
  late final StreamSubscription<String> _errorSubscription;

  @override
  void onInit() {
    super.onInit();
    _messageSubscription = _service.receivedMessages.listen(
      (message) => lastReceivedMessage.value = message,
    );
    _statusSubscription = _service.statusChanges.listen(_handleStatus);
    _errorSubscription = _service.errors.listen(
      (message) => errorMessage.value = message,
    );
  }

  Future<void> startServer() async {
    if (isServerRunning.value) {
      errorMessage.value = 'The receiver server is already running.';
      return;
    }
    errorMessage.value = null;
    final address = await _service.startServer(port: defaultPort);
    localIpAddress.value = address ?? 'Not available';
    isServerRunning.value = _service.isServerRunning;
  }

  Future<void> stopServer() async {
    errorMessage.value = null;
    await _service.stopServer();
    isServerRunning.value = false;
    isConnectedToHost.value = false;
    connectionStatus.value = ConnectionStatus.stopped;
  }

  void _handleStatus(ConnectionStatus status) {
    connectionStatus.value = status;
    isServerRunning.value = _service.isServerRunning;
    isConnectedToHost.value = status == ConnectionStatus.connected;
  }

  @override
  void onClose() {
    unawaited(_service.stopServer());
    _messageSubscription.cancel();
    _statusSubscription.cancel();
    _errorSubscription.cancel();
    super.onClose();
  }
}
