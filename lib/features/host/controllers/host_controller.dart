import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/connection_status.dart';
import '../../../models/receiver_session.dart';
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
  final receiverIpInputController = TextEditingController();
  final portController = TextEditingController(text: '5050');
  final audioPortController = TextEditingController(text: '5051');
  final testMessageController = TextEditingController(text: 'Hello Receiver');
  final connectionStatus = ConnectionStatus.disconnected.obs;
  final lastSentMessage = ''.obs;
  final errorMessage = RxnString();
  final audioStatus = AudioStreamStatus.idle.obs;
  final receiverCount = 0.obs;
  final receiverSessions = <ReceiverSession>[].obs;
  final configuredReceiverIps = <String>[].obs;
  late final StreamSubscription<ConnectionStatus> _statusSubscription;
  late final StreamSubscription<String> _errorSubscription;
  StreamSubscription<AudioStreamStatus>? _audioStatusSubscription;
  StreamSubscription<String>? _audioErrorSubscription;
  StreamSubscription<ReceiverSession>? _sessionSubscription;
  late final StreamSubscription<ReceiverSession> _controlSessionSubscription;

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
    _controlSessionSubscription = _service.controlSessionChanges.listen(
      _updateSession,
    );
    final audioService = _audioService;
    if (audioService != null) {
      _audioStatusSubscription = audioService.statusChanges.listen(
        (status) => audioStatus.value = status,
      );
      _audioErrorSubscription = audioService.errors.listen(
        (message) => errorMessage.value = message,
      );
      _sessionSubscription = audioService.sessionChanges.listen(_updateSession);
    }
  }

  Future<void> connect() async {
    errorMessage.value = null;
    final addresses = _receiverAddresses();
    final port = int.tryParse(portController.text.trim());
    if (addresses.isEmpty) {
      return _showError('Enter the receiver IP address.');
    }
    for (final address in addresses) {
      final parsedIp = InternetAddress.tryParse(address);
      if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
        return _showError('Enter a valid IPv4 address.');
      }
    }
    if (port == null || port < 1 || port > 65535) {
      return _showError('Enter a port between 1 and 65535.');
    }
    await _service.connectToReceivers(
      receivers: addresses
          .map(
            (address) => ReceiverSession(
              id: address,
              ipAddress: address,
              port: port,
              controlStatus: ControlConnectionStatus.connecting,
            ),
          )
          .toList(growable: false),
    );
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

  Future<void> startSystemAudioStream() async {
    errorMessage.value = null;
    final audioService = _audioService;
    final addresses = _receiverAddresses();
    final port = int.tryParse(audioPortController.text.trim());
    if (audioService == null) {
      return _showError('Audio service is unavailable.');
    }
    if (addresses.isEmpty) {
      return _showError('Enter at least one receiver IP address.');
    }
    for (final address in addresses) {
      final parsedIp = InternetAddress.tryParse(address);
      if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
        return _showError('Enter valid IPv4 receiver addresses.');
      }
    }
    if (port == null || port < 1 || port > 65535) {
      return _showError('Enter an audio port between 1 and 65535.');
    }
    receiverCount.value = addresses.length;
    await audioService.startStreaming(ipAddresses: addresses, port: port);
  }

  Future<void> stopSystemAudioStream() async {
    errorMessage.value = null;
    await _audioService?.stopStreaming();
    receiverCount.value = 0;
    receiverSessions.clear();
  }

  List<String> _receiverAddresses() {
    if (configuredReceiverIps.isNotEmpty) {
      return configuredReceiverIps.toList(growable: false);
    }
    return receiverIpController.text
        .split(RegExp(r'[\s,;]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  void addReceiverIp() {
    final address = receiverIpInputController.text.trim();
    final parsed = InternetAddress.tryParse(address);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return _showError('Enter a valid IPv4 receiver address.');
    }
    if (configuredReceiverIps.contains(address)) {
      return _showError('That receiver is already in the list.');
    }
    configuredReceiverIps.add(address);
    receiverIpInputController.clear();
    errorMessage.value = null;
  }

  void removeReceiverIp(String address) =>
      configuredReceiverIps.remove(address);

  Future<void> adjustReceiverCalibration(
    ReceiverSession session,
    int deltaMilliseconds,
  ) async {
    final audioService = _audioService;
    if (audioService == null) return;
    await audioService.setReceiverCalibration(
      receiverId: session.id,
      calibrationMicros:
          session.playbackCalibrationMicros + deltaMilliseconds * 1000,
    );
  }

  void _updateSession(ReceiverSession session) {
    final index = receiverSessions.indexWhere((item) => item.id == session.id);
    if (index == -1) {
      receiverSessions.add(session);
    } else {
      receiverSessions[index] = session;
      receiverSessions.refresh();
    }
  }

  void _showError(String message) => errorMessage.value = message;

  @override
  void onClose() {
    unawaited(_service.disconnect());
    _statusSubscription.cancel();
    _errorSubscription.cancel();
    _audioStatusSubscription?.cancel();
    _audioErrorSubscription?.cancel();
    _sessionSubscription?.cancel();
    _controlSessionSubscription.cancel();
    receiverIpController.dispose();
    receiverIpInputController.dispose();
    portController.dispose();
    audioPortController.dispose();
    testMessageController.dispose();
    super.onClose();
  }
}
