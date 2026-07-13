import 'dart:async';

import 'package:get/get.dart';

import '../../../app/constants/app_constants.dart';
import '../../../models/connection_status.dart';
import '../../../models/control_command.dart';
import '../../../models/receiver_session.dart';
import '../../../models/audio_stream_status.dart';
import '../../../services/connection_service.dart';
import '../../../services/udp_audio_service.dart';
import '../../../services/device_discovery_service.dart';
import '../../../services/pairing_store.dart';

class ReceiverController extends GetxController {
  ReceiverController({
    ConnectionService? connectionService,
    AudioStreamService? audioService,
    DeviceDiscoveryService? discoveryService,
    PairingStore? pairingStore,
  }) : _service = connectionService ?? Get.find<ConnectionService>(),
       _audioService =
           audioService ??
           (Get.isRegistered<AudioStreamService>()
               ? Get.find<AudioStreamService>()
               : null),
       _discoveryService =
           discoveryService ??
           (Get.isRegistered<DeviceDiscoveryService>()
               ? Get.find<DeviceDiscoveryService>()
               : PlaceholderDeviceDiscoveryService()),
       _pairingStore =
           pairingStore ??
           (Get.isRegistered<PairingStore>()
               ? Get.find<PairingStore>()
               : AndroidPairingStore());

  static const defaultPort = 5050;
  final ConnectionService _service;
  final AudioStreamService? _audioService;
  final DeviceDiscoveryService _discoveryService;
  final PairingStore _pairingStore;
  final pairingToken = 'Loading…'.obs;
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
  late final StreamSubscription<ControlEvent> _controlEventSubscription;
  late final StreamSubscription<ReceiverSession> _controlSessionSubscription;
  Timer? _bufferStatusTimer;
  String? _hostSessionId;
  late Future<void> _pairingReady;

  @override
  void onInit() {
    super.onInit();
    _pairingReady = _loadPairingToken();
    _messageSubscription = _service.receivedMessages.listen(
      (message) => lastReceivedMessage.value = message,
    );
    _statusSubscription = _service.statusChanges.listen(_handleStatus);
    _errorSubscription = _service.errors.listen(
      (message) => errorMessage.value = message,
    );
    _controlEventSubscription = _service.controlEvents.listen(
      _handleControlEvent,
    );
    _controlSessionSubscription = _service.controlSessionChanges.listen((
      session,
    ) {
      if (session.controlStatus == ControlConnectionStatus.disconnected) {
        _hostSessionId = null;
        _bufferStatusTimer?.cancel();
        _bufferStatusTimer = null;
      }
      if (session.controlStatus == ControlConnectionStatus.disconnected &&
          isServerRunning.value &&
          (_audioService?.isReceiving ?? false)) {
        unawaited(stopAudioReceiver());
      }
    });
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

  Future<void> _loadPairingToken() async {
    final existing = await _pairingStore.readToken();
    final token = existing ?? AndroidPairingStore.generateToken();
    pairingToken.value = token;
    if (existing == null) await _pairingStore.writeToken(token);
    _service.setPairingToken(token);
  }

  Future<void> startServer() async {
    if (isServerRunning.value) {
      errorMessage.value = 'The receiver server is already running.';
      return;
    }
    errorMessage.value = null;
    await _pairingReady;
    final address = await _service.startServer(port: defaultPort);
    localIpAddress.value = address ?? 'Not available';
    isServerRunning.value = _service.isServerRunning;
    if (isServerRunning.value) {
      await _discoveryService.startResponder(
        deviceId: address ?? 'receiver',
        deviceName: 'Sync Audio Receiver',
        controlPort: defaultPort,
      );
    }
    if (_audioService != null && !_audioService.isReceiving) {
      await startAudioReceiver();
    }
  }

  Future<void> stopServer() async {
    errorMessage.value = null;
    await _service.stopServer();
    await _discoveryService.stopResponder();
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

  void _handleControlEvent(ControlEvent event) {
    _hostSessionId = event.sourceId;
    _bufferStatusTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sendBufferStatus(),
    );
    switch (event.command.type) {
      case ControlCommandType.streamPrepare:
      case ControlCommandType.streamStart:
        if (isServerRunning.value && !(_audioService?.isReceiving ?? false)) {
          unawaited(startAudioReceiver());
        }
      case ControlCommandType.streamStop:
        if (_audioService?.isReceiving ?? false) {
          unawaited(stopAudioReceiver());
        }
      case ControlCommandType.setPlaybackOffset:
        final offset = int.tryParse(event.command.arguments.first);
        final audioService = _audioService;
        if (offset != null && audioService != null) {
          unawaited(audioService.applyPlaybackOffset(offset));
        }
      default:
        break;
    }
  }

  void _sendBufferStatus() {
    final hostId = _hostSessionId;
    final audioService = _audioService;
    if (hostId == null || audioService == null) return;
    unawaited(
      _service.sendControlCommand(
        receiverId: hostId,
        command: ControlCommand(
          type: ControlCommandType.bufferStatus,
          arguments: [
            '${audioService.bufferedDurationMicros}',
            '${audioService.bufferedPackets}',
          ],
        ),
      ),
    );
  }

  void _handleStatus(ConnectionStatus status) {
    connectionStatus.value = status;
    isServerRunning.value = _service.isServerRunning;
    isConnectedToHost.value = status == ConnectionStatus.connected;
  }

  @override
  void onClose() {
    unawaited(_service.stopServer());
    unawaited(_discoveryService.stopResponder());
    _messageSubscription.cancel();
    _statusSubscription.cancel();
    _errorSubscription.cancel();
    _audioStatusSubscription?.cancel();
    _audioErrorSubscription?.cancel();
    _controlEventSubscription.cancel();
    _controlSessionSubscription.cancel();
    _bufferStatusTimer?.cancel();
    unawaited(_audioService?.stopReceiver());
    super.onClose();
  }
}
