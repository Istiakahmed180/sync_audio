import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/connection_status.dart';
import '../../../services/connection_service.dart';

class HostController extends GetxController {
  HostController({ConnectionService? connectionService})
    : _service = connectionService ?? Get.find<ConnectionService>();

  final ConnectionService _service;
  final receiverIpController = TextEditingController();
  final portController = TextEditingController(text: '5050');
  final testMessageController = TextEditingController(text: 'Hello Receiver');
  final connectionStatus = ConnectionStatus.disconnected.obs;
  final lastSentMessage = ''.obs;
  final errorMessage = RxnString();
  late final StreamSubscription<ConnectionStatus> _statusSubscription;
  late final StreamSubscription<String> _errorSubscription;

  bool get isConnected => connectionStatus.value == ConnectionStatus.connected;
  bool get isConnecting =>
      connectionStatus.value == ConnectionStatus.connecting;

  @override
  void onInit() {
    super.onInit();
    _statusSubscription = _service.statusChanges.listen(
      (status) => connectionStatus.value = status,
    );
    _errorSubscription = _service.errors.listen(
      (message) => errorMessage.value = message,
    );
  }

  Future<void> connect() async {
    errorMessage.value = null;
    final ip = receiverIpController.text.trim();
    final port = int.tryParse(portController.text.trim());
    final parsedIp = InternetAddress.tryParse(ip);
    if (ip.isEmpty) {
      return _showError('Enter the receiver IP address.');
    }
    if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
      return _showError('Enter a valid IPv4 address.');
    }
    if (port == null || port < 1 || port > 65535) {
      return _showError('Enter a port between 1 and 65535.');
    }
    await _service.connect(ipAddress: ip, port: port);
  }

  Future<void> disconnect() async {
    errorMessage.value = null;
    await _service.disconnect();
  }

  Future<void> sendTestMessage() async {
    errorMessage.value = null;
    final message = testMessageController.text.trim();
    if (!isConnected) {
      return _showError('Connect to a receiver before sending a message.');
    }
    if (message.isEmpty) {
      return _showError('Enter a test message.');
    }
    await _service.sendMessage(message);
    lastSentMessage.value = message;
  }

  void _showError(String message) => errorMessage.value = message;

  @override
  void onClose() {
    unawaited(_service.disconnect());
    _statusSubscription.cancel();
    _errorSubscription.cancel();
    receiverIpController.dispose();
    portController.dispose();
    testMessageController.dispose();
    super.onClose();
  }
}
