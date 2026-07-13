import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/connection_status.dart';
import '../../../services/connection_service.dart';
import '../../../models/audio_stream_status.dart';
import '../../../services/udp_audio_service.dart';

class HostController extends GetxController {
  HostController({
    ConnectionService? connectionService,
    AudioStreamService? audioService,
  }) : _service = connectionService ?? Get.find<ConnectionService>(),
       _audioService =
           audioService ??
           (Get.isRegistered<AudioStreamService>()
               ? Get.find<AudioStreamService>()
               : null);

  final ConnectionService _service;
  final AudioStreamService? _audioService;
  final receiverIpController = TextEditingController();
  final portController = TextEditingController(text: '5050');
  final audioPortController = TextEditingController(text: '5051');
  final testMessageController = TextEditingController(text: 'Hello Receiver');
  final connectionStatus = ConnectionStatus.disconnected.obs;
  final lastSentMessage = ''.obs;
  final errorMessage = RxnString();
  final audioStatus = AudioStreamStatus.idle.obs;
  late final StreamSubscription<ConnectionStatus> _statusSubscription;
  late final StreamSubscription<String> _errorSubscription;
  StreamSubscription<AudioStreamStatus>? _audioStatusSubscription;
  StreamSubscription<String>? _audioErrorSubscription;

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
    final audioService = _audioService;
    if (audioService != null) {
      _audioStatusSubscription = audioService.statusChanges.listen(
        (status) => audioStatus.value = status,
      );
      _audioErrorSubscription = audioService.errors.listen(
        (message) => errorMessage.value = message,
      );
    }
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

  Future<void> startTestTone() async {
    errorMessage.value = null;
    final audioService = _audioService;
    final ip = receiverIpController.text.trim();
    final port = int.tryParse(audioPortController.text.trim());
    final parsedIp = InternetAddress.tryParse(ip);
    if (audioService == null) {
      return _showError('Audio service is unavailable.');
    }
    if (ip.isEmpty) return _showError('Enter the receiver IP address.');
    if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
      return _showError('Enter a valid IPv4 address.');
    }
    if (port == null || port < 1 || port > 65535) {
      return _showError('Enter an audio port between 1 and 65535.');
    }
    await audioService.startStreaming(ipAddress: ip, port: port);
  }

  Future<void> stopTestTone() async {
    errorMessage.value = null;
    await _audioService?.stopStreaming();
  }

  void _showError(String message) => errorMessage.value = message;

  @override
  void onClose() {
    unawaited(_service.disconnect());
    _statusSubscription.cancel();
    _errorSubscription.cancel();
    _audioStatusSubscription?.cancel();
    _audioErrorSubscription?.cancel();
    receiverIpController.dispose();
    portController.dispose();
    audioPortController.dispose();
    testMessageController.dispose();
    super.onClose();
  }
}
