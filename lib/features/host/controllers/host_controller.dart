import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/audio_stream_status.dart';
import '../../../models/connection_status.dart';
import '../../../models/control_command.dart';
import '../../../models/receiver_session.dart';
import '../../../services/audio_codec.dart';
import '../../../services/background_connection_service.dart';
import '../../../services/calibration_store.dart';
import '../../../services/connection_service.dart';
import '../../../services/device_discovery_service.dart';
import '../../../services/latency_metrics.dart';
import '../../../services/native_audio_runtime.dart';
import '../../../services/paired_device_store.dart';
import '../../../shared/widgets/app_error_notifier.dart';
import '../../../shared/widgets/app_notification_service.dart';
import '../../../services/udp_audio_service.dart';
import '../../../features/settings/controllers/settings_controller.dart';

class HostController extends GetxController {
  HostController({
    ConnectionService? connectionService,
    AudioStreamService? audioService,
    CalibrationStore? calibrationStore,
    DeviceDiscoveryService? discoveryService,
    NativeAudioRuntime? nativeAudioRuntime,
  }) : _service = connectionService ?? Get.find<ConnectionService>(),
       _audioService =
           audioService ??
           (Get.isRegistered<AudioStreamService>()
               ? Get.find<AudioStreamService>()
               : null),
       _calibrationStore =
           calibrationStore ??
           (Get.isRegistered<CalibrationStore>()
               ? Get.find<CalibrationStore>()
               : SharedPrefsCalibrationStore()),
       _discoveryService =
           discoveryService ??
           (Get.isRegistered<DeviceDiscoveryService>()
               ? Get.find<DeviceDiscoveryService>()
               : PlaceholderDeviceDiscoveryService()),
       _nativeAudioRuntime =
           nativeAudioRuntime ??
           (Get.isRegistered<NativeAudioRuntime>()
               ? Get.find<NativeAudioRuntime>()
               : NativeAudioRuntime());

  final ConnectionService _service;
  final AudioStreamService? _audioService;
  final CalibrationStore _calibrationStore;
  final DeviceDiscoveryService _discoveryService;
  final NativeAudioRuntime _nativeAudioRuntime;
  final pairingTokenController = TextEditingController();
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
  final receiverPairingControllers = <String, TextEditingController>{}.obs;
  final codecPreference = AudioCodecPreference.auto.obs;
  final latencyMode = LatencyMode.balanced.obs;
  final adaptiveJitter = true.obs;
  final driftCorrection = true.obs;
  final maximumDriftCorrectionPpm = 200.obs;
  final diagnostics = <String, Object>{}.obs;
  final _streamSessionId = 'stream-${DateTime.now().microsecondsSinceEpoch}';
  late final StreamSubscription<ConnectionStatus> _statusSubscription;
  late final StreamSubscription<String> _errorSubscription;
  StreamSubscription<AudioStreamStatus>? _audioStatusSubscription;
  StreamSubscription<String>? _audioErrorSubscription;
  StreamSubscription<ReceiverSession>? _sessionSubscription;
  Timer? _diagnosticTimer;
  Worker? _errorSnackbarWorker;
  late final StreamSubscription<ReceiverSession> _controlSessionSubscription;
  ConnectionStatus? _lastNotifiedConnectionStatus;
  bool _suppressNextDisconnectedNotification = false;

  bool get isConnected => connectionStatus.value == ConnectionStatus.connected;

  bool get isConnecting =>
      connectionStatus.value == ConnectionStatus.connecting;
  bool _nativeHostActive = false;
  final _pairedStore = PairedDeviceStore();
  final receiverVolumes = <String, double>{}.obs;
  final receiverMuted = <String, bool>{}.obs;
  final pairedDevices = <PairedDevice>[].obs;
  final savedGroups = <DeviceGroup>[].obs;
  final _statsStartTime = DateTime.now();
  bool _statsActive = false;

  /// The TCP control service and UDP audio service use different session IDs
  /// for the same receiver (for example, `192.168.1.10` vs
  /// `192.168.1.10:5051`). Keep those internal IDs intact, but expose one
  /// logical receiver card to the UI.
  List<ReceiverSession> get displayReceiverSessions {
    final grouped = <String, List<ReceiverSession>>{};
    for (final session in receiverSessions) {
      grouped.putIfAbsent(session.ipAddress, () => []).add(session);
    }
    return grouped.values.map(_mergeDisplaySessions).toList(growable: false);
  }

  double volumeForReceiver(String address) => receiverVolumes[address] ?? 1.0;
  bool isMuted(String address) => receiverMuted[address] ?? false;

  Future<void> loadPairedDevices() async {
    pairedDevices.value = await _pairedStore.loadPaired();
  }

  Future<void> loadSavedGroups() async {
    savedGroups.value = await _pairedStore.loadGroups();
  }

  Future<void> saveCurrentAsGroup(String groupName) async {
    if (configuredReceiverIps.isEmpty) return;
    await _pairedStore.saveGroup(
      DeviceGroup(name: groupName, deviceIps: configuredReceiverIps.toList()),
    );
    await loadSavedGroups();
  }

  Future<void> applyGroup(DeviceGroup group) async {
    configuredReceiverIps.clear();
    for (final ip in group.deviceIps) {
      configuredReceiverIps.add(ip);
      receiverPairingControllers[ip] ??= TextEditingController();
    }
  }

  Future<void> deleteGroup(String name) async {
    await _pairedStore.removeGroup(name);
    await loadSavedGroups();
  }

  void setReceiverVolume(String address, double volume) {
    receiverVolumes[address] = volume;
    if (volume <= 0.0) {
      receiverMuted[address] = true;
    } else if (volume > 0.0) {
      receiverMuted[address] = false;
    }
  }

  void toggleMute(String address) {
    receiverMuted[address] = !(receiverMuted[address] ?? false);
  }

  void _startStats() {
    _statsActive = true;
  }

  void _stopStats() {
    if (!_statsActive) return;
    _statsActive = false;
    final elapsed = DateTime.now().difference(_statsStartTime);
    final minutes = elapsed.inMinutes;
    if (minutes <= 0) return;
    final totalMb = 0.0;
    final lossCount = (diagnostics['droppedPacketCount'] as int? ?? 0);
    if (Get.isRegistered<SettingsController>()) {
      Get.find<SettingsController>().addStreamStats(
        minutes,
        totalMb,
        lossCount,
      );
    }
  }

  void _cleanupDiagnosticTimer() {
    _diagnosticTimer?.cancel();
    _diagnosticTimer = null;
  }

  void _ensureDiagnosticTimer() {
    final audioService = _audioService;
    if (audioService == null || _diagnosticTimer != null) return;
    _diagnosticTimer = Timer.periodic(
      const Duration(milliseconds: 1000),
      (_) => unawaited(_refreshDiagnostics(audioService)),
    );
  }

  ReceiverSession? receiverSessionFor(String address) {
    final index = receiverSessions.indexWhere(
      (session) => session.id == address,
    );
    return index == -1 ? null : receiverSessions[index];
  }

  @override
  void onInit() {
    super.onInit();
    _statusSubscription = _service.statusChanges.listen(_handleStatus);
    _errorSubscription = _service.errors.listen((message) {
      errorMessage.value = message;
      _suppressNextDisconnectedNotification = true;
      unawaited(
        AppNotificationService.show(
          title: 'Connection error',
          message: message,
          id: 1001,
        ),
      );
    });
    _errorSnackbarWorker = ever<String?>(errorMessage, (message) {
      if (message != null) showAppErrorSnackbar(message);
    });
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
      _diagnosticTimer = Timer.periodic(
        const Duration(milliseconds: 1000),
        (_) => unawaited(_refreshDiagnostics(audioService)),
      );
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
    final pairingText = _pairingInputFor(addresses);
    if (!_isValidPairingInput(pairingText, addresses)) {
      return _showError(
        'Enter the 8-digit Receiver pairing code, or one code per IP address.',
      );
    }
    _service.setPairingToken(pairingText);
    final perReceiverTokens = <String, String>{};
    for (final entry in pairingText.split(',')) {
      final parts = entry.split('=').map((part) => part.trim()).toList();
      if (parts.length == 2 && addresses.contains(parts.first)) {
        perReceiverTokens[parts.first] = parts.last;
      }
    }
    _service.setPairingTokens(perReceiverTokens);
    final receivers = <ReceiverSession>[];
    for (final address in addresses) {
      final calibration = await _calibrationStore.read(address) ?? 0;
      receivers.add(
        ReceiverSession(
          id: address,
          ipAddress: address,
          port: port,
          controlStatus: ControlConnectionStatus.connecting,
          playbackCalibrationMicros: calibration,
        ),
      );
    }
    await _service.connectToReceivers(receivers: receivers);
  }

  Future<void> disconnect() async {
    errorMessage.value = null;
    _nativeHostActive = false;
    await _service.disconnect();
  }

  Future<void> connectReceiver(String address) async {
    errorMessage.value = null;
    final port = int.tryParse(portController.text.trim());
    final pairingCode = receiverPairingControllers[address]?.text.trim() ?? '';
    if (InternetAddress.tryParse(address)?.type != InternetAddressType.IPv4) {
      return _showError('Enter a valid IPv4 receiver address.');
    }
    if (port == null || port < 1 || port > 65535) {
      return _showError('Enter a port between 1 and 65535.');
    }
    if (!RegExp(r'^\d{8}$').hasMatch(pairingCode)) {
      return _showError('Enter the 8-digit pairing code for $address.');
    }
    _service.setPairingToken(null);
    _service.setPairingTokens({address: pairingCode});
    final calibration = await _calibrationStore.read(address) ?? 0;
    await _service.connectToReceivers(
      receivers: [
        ReceiverSession(
          id: address,
          ipAddress: address,
          port: port,
          controlStatus: ControlConnectionStatus.connecting,
          playbackCalibrationMicros: calibration,
        ),
      ],
    );
  }

  Future<void> disconnectReceiver(String address) async {
    errorMessage.value = null;
    await _service.disconnectFrom(address);
  }

  void _handleStatus(ConnectionStatus status) {
    final previous = _lastNotifiedConnectionStatus;
    connectionStatus.value = status;
    if (status == ConnectionStatus.connecting ||
        status == ConnectionStatus.connected) {
      unawaited(BackgroundConnectionService.start());
    } else if (status == ConnectionStatus.disconnected ||
        status == ConnectionStatus.error ||
        status == ConnectionStatus.stopped) {
      unawaited(BackgroundConnectionService.stop());
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
      ConnectionStatus.connecting => (
        'Connecting',
        'Connecting to the Receiver…',
      ),
      ConnectionStatus.connected => (
        'Connected',
        'The Host is ready to send audio.',
      ),
      ConnectionStatus.error => (
        'Connection error',
        'The Receiver connection failed.',
      ),
      ConnectionStatus.disconnected when previous != null => (
        'Disconnected',
        'The Host is no longer connected to Receivers.',
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
    _nativeHostActive = false;
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
    await audioService.selectCodec(codecPreference.value);
    final pairingText = _pairingInputFor(addresses);
    final nativeEligible =
        audioService.activeCodecType == AudioCodecType.pcm16 &&
        !pairingText.contains('=');
    await audioService.configureLatency(
      mode: latencyMode.value,
      adaptiveJitter: adaptiveJitter.value,
      driftCorrection: driftCorrection.value,
      maximumDriftCorrectionPpm: maximumDriftCorrectionPpm.value,
    );
    if (pairingText.isNotEmpty && !pairingText.contains('=')) {
      await audioService.setSessionSecurity(
        pairingToken: pairingText,
        sessionId: _streamSessionId,
      );
    }
    final commandArguments = <String>[
      _streamSessionId,
      '0',
      audioService.activeCodecType.name,
      if (nativeEligible) 'native',
    ];
    await _sendControlCommand(
      addresses,
      ControlCommandType.streamPrepare,
      commandArguments,
    );
    if (nativeEligible) {
      try {
        await _nativeAudioRuntime.startNativeHostStream(
          destinations: addresses,
          port: port,
          codec: audioService.activeCodecType,
          encrypted: pairingText.isNotEmpty,
          latencyMode: latencyMode.value,
          sessionId: _streamSessionId,
          pairingToken: pairingText.isEmpty ? null : pairingText,
        );
        _nativeHostActive = true;
      } catch (_) {
        assert(() {
          debugPrint(
            'Native low-latency audio is unavailable; using Dart fallback.',
          );
          return true;
        }());
      }
    }
    if (_nativeHostActive) {
      _startStats();
      await _sendControlCommand(
        addresses,
        ControlCommandType.streamStart,
        commandArguments,
      );
      _ensureDiagnosticTimer();
      await AppNotificationService.show(
        title: 'System audio streaming',
        message: 'Audio is being sent to the connected Receivers.',
        id: 1002,
      );
      return;
    }
    await audioService.startStreaming(ipAddresses: addresses, port: port);
    _startStats();
    await _sendControlCommand(
      addresses,
      ControlCommandType.streamStart,
      commandArguments,
    );
    _ensureDiagnosticTimer();
    await AppNotificationService.show(
      title: 'System audio streaming',
      message: 'Audio is being sent to the connected Receivers.',
      id: 1002,
    );
  }

  Future<void> selectCodec(AudioCodecPreference preference) async {
    codecPreference.value = preference;
    await _audioService?.selectCodec(preference);
  }

  Future<void> configureLatency(LatencyMode mode) async {
    latencyMode.value = mode;
    await _audioService?.configureLatency(
      mode: mode,
      adaptiveJitter: adaptiveJitter.value,
      driftCorrection: driftCorrection.value,
      maximumDriftCorrectionPpm: maximumDriftCorrectionPpm.value,
    );
  }

  Future<void> _refreshDiagnostics(AudioStreamService audioService) async {
    diagnostics.value = _nativeHostActive
        ? await _nativeAudioRuntime.diagnostics()
        : audioService.diagnosticsSnapshot;
  }

  Future<void> stopSystemAudioStream() async {
    errorMessage.value = null;
    _stopStats();
    _cleanupDiagnosticTimer();
    await _sendControlCommand(
      _receiverAddresses(),
      ControlCommandType.streamStop,
      [_streamSessionId],
    );
    if (_nativeHostActive) {
      await _nativeAudioRuntime.stopNativeHostStream();
      _nativeHostActive = false;
    }
    await _audioService?.stopStreaming();
    receiverCount.value = 0;
    receiverSessions.clear();
    await AppNotificationService.show(
      title: 'System audio stopped',
      message: 'Audio streaming has been stopped.',
      id: 1002,
    );
  }

  Future<void> _sendControlCommand(
    List<String> addresses,
    ControlCommandType type,
    List<String> arguments,
  ) async {
    for (final address in addresses) {
      await _service.sendControlCommand(
        receiverId: address,
        command: ControlCommand(type: type, arguments: arguments),
      );
    }
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

  String _pairingInputFor(List<String> addresses) {
    if (configuredReceiverIps.isEmpty) {
      return pairingTokenController.text.trim();
    }
    final codes = <String, String>{
      for (final address in addresses)
        address: receiverPairingControllers[address]?.text.trim() ?? '',
    };
    if (codes.values.every((code) => code == codes.values.first)) {
      return codes.values.first;
    }
    return codes.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(',');
  }

  bool _isValidPairingInput(String value, List<String> addresses) {
    final codePattern = RegExp(r'^\d{8}$');
    if (codePattern.hasMatch(value)) return true;
    final entries = value.split(',');
    if (entries.length != addresses.length) return false;
    final mappedAddresses = <String>{};
    for (final entry in entries) {
      final parts = entry.split('=').map((part) => part.trim()).toList();
      if (parts.length != 2 ||
          !addresses.contains(parts[0]) ||
          !codePattern.hasMatch(parts[1]) ||
          !mappedAddresses.add(parts[0])) {
        return false;
      }
    }
    return mappedAddresses.length == addresses.length;
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
    receiverPairingControllers[address] = TextEditingController(
      text: pairingTokenController.text.trim(),
    );
    receiverIpInputController.clear();
    pairingTokenController.clear();
    errorMessage.value = null;
  }

  void removeReceiverIp(String address) {
    configuredReceiverIps.remove(address);
    receiverPairingControllers.remove(address)?.dispose();
  }

  Future<void> discoverReceivers() async {
    errorMessage.value = null;
    final devices = await _discoveryService.discover();
    if (devices.isEmpty) {
      _showError('No receivers were found on this Wi-Fi network.');
      return;
    }
    for (final device in devices) {
      if (!configuredReceiverIps.contains(device.ipAddress)) {
        configuredReceiverIps.add(device.ipAddress);
        receiverPairingControllers[device.ipAddress] = TextEditingController();
      }
    }
  }

  Future<void> adjustReceiverCalibration(
    ReceiverSession session,
    int deltaMilliseconds,
  ) async {
    final audioService = _audioService;
    if (audioService == null) return;
    final calibrationMicros =
        session.playbackCalibrationMicros + deltaMilliseconds * 1000;
    final audioSession = audioService.receiverSessions
        .cast<ReceiverSession?>()
        .firstWhere(
          (candidate) => candidate?.ipAddress == session.ipAddress,
          orElse: () => null,
        );
    await audioService.setReceiverCalibration(
      receiverId: audioSession?.id ?? session.id,
      calibrationMicros: calibrationMicros,
    );
    await _calibrationStore.write(session.id, calibrationMicros);
    final currentIndex = receiverSessions.indexWhere(
      (s) => s.ipAddress == session.ipAddress,
    );
    final clockOffset = currentIndex != -1
        ? receiverSessions[currentIndex].clockOffsetMicros
        : session.clockOffsetMicros;
    await _service.sendControlCommand(
      receiverId: session.id,
      command: ControlCommand(
        type: ControlCommandType.setPlaybackOffset,
        arguments: ['${clockOffset + calibrationMicros}'],
      ),
    );
    final index = receiverSessions.indexWhere(
      (item) => item.ipAddress == session.ipAddress,
    );
    if (index != -1) {
      receiverSessions[index] = session.copyWith(
        playbackCalibrationMicros: calibrationMicros,
      );
      receiverSessions.refresh();
    }
  }

  ReceiverSession _mergeDisplaySessions(List<ReceiverSession> sessions) {
    final control = sessions.cast<ReceiverSession?>().firstWhere(
      (session) => session?.id == session?.ipAddress,
      orElse: () => null,
    );
    final audio = sessions.cast<ReceiverSession?>().firstWhere(
      (session) => session?.id != session?.ipAddress,
      orElse: () => null,
    );
    final base = control ?? sessions.first;
    if (audio == null) return base;
    return base.copyWith(
      status: audio.status,
      clockOffsetMicros: audio.clockOffsetMicros,
      clockDriftPpm: audio.clockDriftPpm,
      playbackCalibrationMicros: audio.playbackCalibrationMicros,
      roundTripTimeMicros: audio.roundTripTimeMicros,
      lastSyncMicros: audio.lastSyncMicros,
    );
  }

  void _updateSession(ReceiverSession session) {
    final index = receiverSessions.indexWhere((item) => item.id == session.id);
    if (index == -1) {
      receiverSessions.add(session);
    } else {
      // Clock-sync updates come from the connection service and do not carry
      // the Host-side manual calibration. Keep that value across PING/PONG
      // updates instead of resetting it to zero.
      final current = receiverSessions[index];
      receiverSessions[index] = session.copyWith(
        playbackCalibrationMicros: current.playbackCalibrationMicros,
      );
      receiverSessions.refresh();
    }
  }

  void _showError(String message) => errorMessage.value = message;

  @override
  void onClose() {
    unawaited(_service.disconnect());
    unawaited(_nativeAudioRuntime.stopNativeHostStream());
    _statusSubscription.cancel();
    _errorSubscription.cancel();
    _audioStatusSubscription?.cancel();
    _audioErrorSubscription?.cancel();
    _sessionSubscription?.cancel();
    _diagnosticTimer?.cancel();
    _errorSnackbarWorker?.dispose();
    _controlSessionSubscription.cancel();
    receiverIpController.dispose();
    receiverIpInputController.dispose();
    portController.dispose();
    audioPortController.dispose();
    testMessageController.dispose();
    pairingTokenController.dispose();
    for (final controller in receiverPairingControllers.values) {
      controller.dispose();
    }
    super.onClose();
  }
}
