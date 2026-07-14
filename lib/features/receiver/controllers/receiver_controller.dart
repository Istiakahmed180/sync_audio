import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../app/constants/app_constants.dart';
import '../../../models/connection_status.dart';
import '../../../models/control_command.dart';
import '../../../models/receiver_session.dart';
import '../../../models/audio_stream_status.dart';
import '../../../services/connection_service.dart';
import '../../../services/udp_audio_service.dart';
import '../../../services/device_discovery_service.dart';
import '../../../services/audio_codec.dart';
import '../../../services/background_connection_service.dart';
import '../../../services/pairing_store.dart';
import '../../../services/native_audio_runtime.dart';
import '../../../services/latency_metrics.dart';
import '../../../shared/widgets/app_error_notifier.dart';
import '../../../shared/widgets/app_notification_service.dart';

class ReceiverController extends GetxController {
  ReceiverController({
    ConnectionService? connectionService,
    AudioStreamService? audioService,
    DeviceDiscoveryService? discoveryService,
    PairingStore? pairingStore,
    NativeAudioRuntime? nativeAudioRuntime,
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
               : AndroidPairingStore()),
       _nativeAudioRuntime =
           nativeAudioRuntime ??
           (Get.isRegistered<NativeAudioRuntime>()
               ? Get.find<NativeAudioRuntime>()
               : NativeAudioRuntime());

  static const defaultPort = 5050;
  final ConnectionService _service;
  final AudioStreamService? _audioService;
  final DeviceDiscoveryService _discoveryService;
  final PairingStore _pairingStore;
  final NativeAudioRuntime _nativeAudioRuntime;
  final pairingToken = 'Loading…'.obs;
  final connectionStatus = ConnectionStatus.disconnected.obs;
  final localIpAddress = 'Not available'.obs;
  final deviceName = 'My Speaker'.obs;
  final isServerRunning = false.obs;
  final isConnectedToHost = false.obs;
  final lastReceivedMessage = ''.obs;
  final lastSyncPing = ''.obs;
  final errorMessage = RxnString();
  final messageController = TextEditingController();
  final lastSentMessage = ''.obs;
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
  bool _nativeReceiverActive = false;
  Worker? _errorSnackbarWorker;
  String? _hostSessionId;
  String? _pairingTokenValue;
  late Future<void> _pairingReady;
  ConnectionStatus? _lastNotifiedConnectionStatus;
  bool _suppressNextDisconnectedNotification = false;
  bool _hostWasConnected = false;

  @override
  void onInit() {
    super.onInit();
    _pairingReady = _loadPairingToken();
    _messageSubscription = _service.receivedMessages.listen((message) {
      lastReceivedMessage.value = message;
      unawaited(
        AppNotificationService.show(
          title: 'New message from Host',
          message: message,
          id: 1004,
        ),
      );
    });
    _statusSubscription = _service.statusChanges.listen(_handleStatus);
    _errorSubscription = _service.errors.listen((message) {
      errorMessage.value = message;
      _suppressNextDisconnectedNotification = true;
      unawaited(
        AppNotificationService.show(
          title: 'Receiver error',
          message: message,
          id: 1001,
        ),
      );
    });
    _errorSnackbarWorker = ever<String?>(errorMessage, (message) {
      if (message != null) showAppErrorSnackbar(message);
    });
    _controlEventSubscription = _service.controlEvents.listen(
      _handleControlEvent,
    );
    _controlSessionSubscription = _service.controlSessionChanges.listen((
      session,
    ) {
      if (session.controlStatus == ControlConnectionStatus.disconnected) {
        final wasConnected = _hostWasConnected;
        _hostWasConnected = false;
        isConnectedToHost.value = false;
        _hostSessionId = null;
        _bufferStatusTimer?.cancel();
        _bufferStatusTimer = null;
        if (wasConnected) {
          unawaited(
            AppNotificationService.show(
              title: 'Host disconnected',
              message: 'The Host connection has ended.',
              id: 1001,
            ),
          );
        }
      }
      if (session.controlStatus == ControlConnectionStatus.disconnected &&
          isServerRunning.value &&
          ((_audioService?.isReceiving ?? false) || _nativeReceiverActive)) {
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
    try {
      final existing = await _pairingStore.readToken();
      final needsRegeneration =
          existing == null || !RegExp(r'^\d{8}$').hasMatch(existing);
      final token = needsRegeneration
          ? AndroidPairingStore.generateToken()
          : existing;
      pairingToken.value = token;
      _pairingTokenValue = token;
      if (needsRegeneration) await _pairingStore.writeToken(token);
      _service.setPairingToken(token);
    } catch (_) {
      final token = AndroidPairingStore.generateToken();
      pairingToken.value = token;
      _pairingTokenValue = token;
      _service.setPairingToken(token);
    }
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
        deviceName: deviceName.value,
        controlPort: defaultPort,
      );
    }
    if (_audioService != null && !_audioService.isReceiving) {
      await startAudioReceiver();
    }
    if (isServerRunning.value) {
      await BackgroundConnectionService.start();
      await AppNotificationService.show(
        title: 'Receiver ready',
        message: 'Share this device IP and pairing code with the Host.',
        id: 1003,
      );
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
    await BackgroundConnectionService.stop();
    await AppNotificationService.show(
      title: 'Receiver stopped',
      message: 'The control and audio listeners are closed.',
      id: 1003,
    );
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
    if (_nativeReceiverActive) {
      await _nativeAudioRuntime.stopNativeReceiver();
      _nativeReceiverActive = false;
    }
    await _audioService?.stopReceiver();
    isAudioReceiverRunning.value = false;
  }

  Future<void> sendMessageToHost() async {
    final message = messageController.text.trim();
    if (message.isEmpty) {
      errorMessage.value = 'Enter a message first.';
      return;
    }
    if (!isConnectedToHost.value) {
      errorMessage.value = 'No Host is connected.';
      return;
    }
    final hostId = _hostSessionId;
    if (hostId == null) {
      errorMessage.value = 'Host session is unavailable.';
      return;
    }
    errorMessage.value = null;
    await _service.sendMessageTo(receiverId: hostId, message: message);
    lastSentMessage.value = message;
    messageController.clear();
  }

  void prepareConnectionInfo() {
    messageController.text =
        'I\'m "$deviceName" — IP: ${localIpAddress.value}:5050, Pairing code: ${pairingToken.value}';
  }

  Future<void> _handleControlEvent(ControlEvent event) async {
    _hostSessionId = event.sourceId;
    if (event.command.type == ControlCommandType.ping) {
      lastSyncPing.value = event.command.line;
    }
    _bufferStatusTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _sendBufferStatus(),
    );
    switch (event.command.type) {
      case ControlCommandType.streamPrepare:
      case ControlCommandType.streamStart:
        final sessionId = event.command.arguments.first;
        final nativeRequested =
            event.command.arguments.length >= 4 &&
            event.command.arguments[3] == 'native' &&
            event.command.arguments[2] == AudioCodecType.pcm16.name;
        final token = _pairingTokenValue;
        if (token != null) {
          await _audioService?.setSessionSecurity(
            pairingToken: token,
            sessionId: sessionId,
          );
        }
        if (event.command.arguments.length == 3) {
          final requested = event.command.arguments[2];
          await _audioService?.selectCodec(
            requested == AudioCodecType.opus.name
                ? AudioCodecPreference.opus
                : AudioCodecPreference.pcm,
          );
        }
        if (isServerRunning.value && nativeRequested) {
          if (_audioService?.isReceiving ?? false) {
            await _audioService?.stopReceiver();
          }
          try {
            await _nativeAudioRuntime.startNativeReceiver(
              port: AppConstants.audioPort,
              latencyMode: LatencyMode.balanced,
              sessionId: sessionId,
              pairingToken: _pairingTokenValue,
            );
            _nativeReceiverActive = true;
            isAudioReceiverRunning.value = true;
          } catch (_) {
            _nativeReceiverActive = false;
            unawaited(startAudioReceiver());
          }
        } else if (isServerRunning.value &&
            !(_audioService?.isReceiving ?? false) &&
            !_nativeReceiverActive) {
          unawaited(startAudioReceiver());
        }
      case ControlCommandType.streamStop:
        if ((_audioService?.isReceiving ?? false) || _nativeReceiverActive) {
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
            '${_nativeReceiverActive ? 0 : audioService.bufferedDurationMicros}',
            '${_nativeReceiverActive ? 0 : audioService.bufferedPackets}',
          ],
        ),
      ),
    );
  }

  void _handleStatus(ConnectionStatus status) {
    final previous = _lastNotifiedConnectionStatus;
    connectionStatus.value = status;
    isServerRunning.value = _service.isServerRunning;
    isConnectedToHost.value = status == ConnectionStatus.connected;
    if (status == ConnectionStatus.disconnected) {
      _hostWasConnected = false;
    }
    if (status == ConnectionStatus.connected) {
      _hostWasConnected = true;
    }
    if (previous == status) return;
    _lastNotifiedConnectionStatus = status;
    if (status == ConnectionStatus.connecting) {
      _suppressNextDisconnectedNotification = false;
    }
    if (status == ConnectionStatus.disconnected &&
        _suppressNextDisconnectedNotification) {
      _suppressNextDisconnectedNotification = false;
      return;
    }
    final notification = switch (status) {
      ConnectionStatus.connected => (
        'Host connected',
        'A Host is connected to this Receiver.',
      ),
      ConnectionStatus.disconnected when previous != null => (
        'Host disconnected',
        'The Host connection has ended.',
      ),
      ConnectionStatus.error => (
        'Receiver error',
        'The Host connection failed.',
      ),
      _ => null,
    };
    if (notification != null) {
      unawaited(
        AppNotificationService.show(
          title: notification.$1,
          message: notification.$2,
          id: 1001,
        ),
      );
    }
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
    _errorSnackbarWorker?.dispose();
    unawaited(_audioService?.stopReceiver());
    unawaited(_nativeAudioRuntime.stopNativeReceiver());
    messageController.dispose();
    super.onClose();
  }
}
