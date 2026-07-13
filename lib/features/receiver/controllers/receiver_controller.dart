import 'dart:async';

import 'package:get/get.dart';

import '../../../app/constants/app_constants.dart';
import '../../../models/connection_status.dart';
import '../../../models/audio_stream_status.dart';
import '../../../services/connection_service.dart';
import '../../../services/udp_audio_service.dart';

class ReceiverController extends GetxController {
  ReceiverController({
    ConnectionService? connectionService,
    AudioStreamService? audioService,
  }) : _service = connectionService ?? Get.find<ConnectionService>(),
       _audioService =
           audioService ??
           (Get.isRegistered<AudioStreamService>()
               ? Get.find<AudioStreamService>()
               : null);

  static const defaultPort = 5050;
  final ConnectionService _service;
  final AudioStreamService? _audioService;
  final connectionStatus = ConnectionStatus.disconnected.obs;
  final localIpAddress = 'Not available'.obs;
  final isServerRunning = false.obs;
  final isConnectedToHost = false.obs;
  final lastReceivedMessage = ''.obs;
  final errorMessage = RxnString();
  final audioStatus = AudioStreamStatus.idle.obs;
  final isAudioReceiverRunning = false.obs;
  late final StreamSubscription<String> _messageSubscription;
  late final StreamSubscription<ConnectionStatus> _statusSubscription;
  late final StreamSubscription<String> _errorSubscription;
  StreamSubscription<AudioStreamStatus>? _audioStatusSubscription;
  StreamSubscription<String>? _audioErrorSubscription;

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
    final audioService = _audioService;
    if (audioService != null) {
      _audioStatusSubscription = audioService.statusChanges.listen((status) {
        audioStatus.value = status;
        isAudioReceiverRunning.value = audioService.isReceiving;
      });
      _audioErrorSubscription = audioService.errors.listen(
        (message) => errorMessage.value = message,
      );
    }
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
    if (_audioService != null && !_audioService.isReceiving) {
      await startAudioReceiver();
    }
  }

  Future<void> stopServer() async {
    errorMessage.value = null;
    await _service.stopServer();
    if (_audioService?.isReceiving ?? false) {
      await stopAudioReceiver();
    }
    isServerRunning.value = false;
    isConnectedToHost.value = false;
    connectionStatus.value = ConnectionStatus.stopped;
  }

  Future<void> startAudioReceiver() async {
    errorMessage.value = null;
    final audioService = _audioService;
    if (audioService == null) {
      errorMessage.value = 'Audio service is unavailable.';
      return;
    }
    await audioService.startReceiver(port: AppConstants.audioPort);
    isAudioReceiverRunning.value = audioService.isReceiving;
  }

  Future<void> stopAudioReceiver() async {
    errorMessage.value = null;
    await _audioService?.stopReceiver();
    isAudioReceiverRunning.value = false;
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
    _audioStatusSubscription?.cancel();
    _audioErrorSubscription?.cancel();
    unawaited(_audioService?.stopReceiver());
    super.onClose();
  }
}
