import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../models/audio_stream_status.dart';
import '../../../models/audio_device.dart';
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
import '../../../services/scheduled_streaming_service.dart';
import '../../../services/udp_audio_service.dart';
import '../../../features/settings/controllers/settings_controller.dart';
import '../../../shared/widgets/app_notification_service.dart';

class HostController extends GetxController {
  static const controlPort = 5050;
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
  // Retained for backwards-compatible controller tests; the UI no longer
  // exposes this because the Receiver control port is fixed at 5050.
  final portController = TextEditingController(text: '$controlPort');
  final audioPortController = TextEditingController(text: '5051');
  final testMessageController = TextEditingController(text: 'Hello Receiver');
  final connectionStatus = ConnectionStatus.disconnected.obs;
  final lastSentMessage = ''.obs;
  final errorMessage = RxnString();
  final audioStatus = AudioStreamStatus.idle.obs;
  final receiverCount = 0.obs;
  final isDiscoveringReceivers = false.obs;
  final isDiscoveryPolling = false.obs;
  final discoveryStatus = 'Search is off. Press Search to find Receivers.'.obs;
  final receiverSessions = <ReceiverSession>[].obs;
  final configuredReceiverIps = <String>[].obs;
  final discoveredDeviceNames = <String, String>{}.obs;
  final discoveredDeviceLatencyMs = <String, int>{}.obs;
  final discoveredDevices = <AudioDevice>[].obs;
  final receiverPairingControllers = <String, TextEditingController>{}.obs;
  final codecPreference = AudioCodecPreference.auto.obs;
  // Stable is the safer default for Wi-Fi + Bluetooth receiver setups.
  final latencyMode = LatencyMode.stable.obs;
  final adaptiveJitter = true.obs;
  final driftCorrection = true.obs;
  final maximumDriftCorrectionPpm = 200.obs;

  bool get isAudioStreaming =>
      _nativeHostActive || (_audioService?.isStreaming ?? false);
  final diagnostics = <String, Object>{}.obs;
  Map<String, Object> get diagnosticsData =>
      Map<String, Object>.from(diagnostics);

  Map<String, Object> receiverDiagnosticsFor(String address) {
    final values = _receiverDiagnostics[address];
    return values == null ? const <String, Object>{} : Map.from(values);
  }

  final _streamSessionId = 'stream-${DateTime.now().microsecondsSinceEpoch}';
  late final StreamSubscription<ConnectionStatus> _statusSubscription;
  StreamSubscription<AudioStreamStatus>? _audioStatusSubscription;
  StreamSubscription<String>? _audioErrorSubscription;
  StreamSubscription<ReceiverSession>? _sessionSubscription;
  StreamSubscription<String>? _notificationActionSubscription;
  late final StreamSubscription<ControlEvent> _diagnosticsSubscription;
  Timer? _diagnosticTimer;
  Timer? _discoveryTimer;
  bool _discoveryInProgress = false;
  bool _showDiscoveryBusyIndicator = true;
  late final StreamSubscription<ReceiverSession> _controlSessionSubscription;
  ConnectionStatus? _lastNotifiedConnectionStatus;
  bool _startingSystemAudio = false;
  bool _autoStreamInProgress = false;
  final _receiverDiagnostics = <String, Map<String, Object>>{};
  final _receiverDiagnosticsUpdatedAt = <String, DateTime>{};
  final _streamingReceiverAddresses = <String>{};
  final _readyReceiverStreamAddresses = <String>{};
  final _restartingAudioSettings = false.obs;

  bool get isConnected => connectionStatus.value == ConnectionStatus.connected;
  bool get isStartingSystemAudio => _startingSystemAudio;
  bool get isRestartingAudioSettings => _restartingAudioSettings.value;

  bool get isConnecting =>
      connectionStatus.value == ConnectionStatus.connecting;
  bool _nativeHostActive = false;
  final _pairedStore = PairedDeviceStore();
  final receiverVolumes = <String, double>{}.obs;
  final receiverMuted = <String, bool>{}.obs;
  final pairedDevices = <PairedDevice>[].obs;
  final savedGroups = <DeviceGroup>[].obs;
  DateTime? _statsStartTime;
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
    unawaited(
      _sendReceiverVolume(address, receiverMuted[address] == true ? 0 : volume),
    );
  }

  void toggleMute(String address) {
    receiverMuted[address] = !(receiverMuted[address] ?? false);
    unawaited(
      _sendReceiverVolume(
        address,
        receiverMuted[address] == true ? 0 : volumeForReceiver(address),
      ),
    );
  }

  Future<void> _sendReceiverVolume(String address, double volume) async {
    final session = receiverSessions.cast<ReceiverSession?>().firstWhere(
      (candidate) => candidate?.ipAddress == address,
      orElse: () => null,
    );
    if (session == null) return;
    await _service.sendControlCommand(
      receiverId: session.id,
      command: ControlCommand(
        type: ControlCommandType.setPlaybackVolume,
        arguments: [volume.toStringAsFixed(4)],
      ),
    );
  }

  void _startStats() {
    _statsActive = true;
    _statsStartTime = DateTime.now();
  }

  void _stopStats() {
    if (!_statsActive) return;
    _statsActive = false;
    final startedAt = _statsStartTime;
    _statsStartTime = null;
    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    final minutes = elapsed.inMinutes;
    if (minutes <= 0) return;
    final currentDiagnostics =
        _audioService?.diagnosticsSnapshot ?? diagnostics;
    final totalBytes = (currentDiagnostics['totalBytesSent'] as int? ?? 0);
    final totalMb = totalBytes / (1024 * 1024);
    final lossCount = (currentDiagnostics['droppedPacketCount'] as int? ?? 0);
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
    // Host connections are app-scoped; opening this screen is only a view of
    // the current session and must not reset an existing background stream.
    connectionStatus.value = _service.status;
    receiverSessions.assignAll(_service.controlSessions);
    if (_audioService != null) {
      audioStatus.value = _audioService.status;
    }
    _statusSubscription = _service.statusChanges.listen(_handleStatus);
    _controlSessionSubscription = _service.controlSessionChanges.listen((
      session,
    ) {
      if (session.controlStatus == ControlConnectionStatus.disconnected) {
        _receiverDiagnostics.remove(session.id);
        _receiverDiagnosticsUpdatedAt.remove(session.id);
      }
      _updateSession(session);
    });
    _diagnosticsSubscription = _service.controlEvents.listen(
      _handleControlEvent,
    );
    if (Platform.isAndroid) {
      _notificationActionSubscription = AppNotificationService.actions.listen(
        _handleNotificationAction,
      );
    }
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
    if (Get.isRegistered<ScheduledStreamingService>()) {
      Get.find<ScheduledStreamingService>().start();
    }
    unawaited(loadSavedGroups());
    unawaited(loadPairedDevices());
  }

  void startDiscoveryPolling({bool showBusyIndicator = true}) {
    if (_discoveryTimer != null) return;
    _showDiscoveryBusyIndicator = showBusyIndicator;
    isDiscoveryPolling.value = true;
    discoveryStatus.value = 'Searching for Receivers…';
    unawaited(discoverReceivers());
    _discoveryTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(discoverReceivers()),
    );
  }

  void stopDiscoveryPolling() {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
    isDiscoveryPolling.value = false;
    isDiscoveringReceivers.value = false;
    discoveryStatus.value = 'Search stopped.';
  }

  void toggleDiscoveryPolling() {
    if (isDiscoveryPolling.value) {
      stopDiscoveryPolling();
    } else {
      startDiscoveryPolling();
    }
  }

  Future<void> connect() async {
    errorMessage.value = null;
    final addresses = _receiverAddresses();
    final port = int.tryParse(portController.text.trim()) ?? controlPort;
    if (addresses.isEmpty) {
      return _showError('Enter the receiver IP address.');
    }
    for (final address in addresses) {
      final parsedIp = InternetAddress.tryParse(address);
      if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
        return _showError('Enter a valid IPv4 address.');
      }
    }
    if (port < 1 || port > 65535) {
      return _showError('Invalid port configured.');
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
    if (_audioService?.isStreaming ?? false) {
      await stopSystemAudioStream();
    }
    await _service.disconnect();
    await BackgroundConnectionService.stop();
  }

  Future<void> connectReceiver(String address) async {
    errorMessage.value = null;
    final port = int.tryParse(portController.text.trim()) ?? controlPort;
    final pairingCode = receiverPairingControllers[address]?.text.trim() ?? '';
    if (InternetAddress.tryParse(address)?.type != InternetAddressType.IPv4) {
      return _showError('Enter a valid IPv4 receiver address.');
    }
    if (port < 1 || port > 65535) {
      return _showError('Invalid port configured.');
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
    final deviceName = discoveredDeviceNames[address] ?? address;
    unawaited(_pairedStore.savePair(ip: address, port: port, name: deviceName));
    unawaited(loadPairedDevices());
  }

  Future<void> disconnectReceiver(String address) async {
    errorMessage.value = null;
    final audioService = _audioService;
    if (audioService?.isStreaming ?? false) {
      // Stop this Receiver before closing its control socket so it cannot
      // keep draining stale PCM when it reconnects.
      await _sendControlCommand(
        [address],
        ControlCommandType.streamStop,
        [_streamSessionId],
      );
      await audioService?.removeReceiver(ipAddress: address);
      _streamingReceiverAddresses.remove(address);
      _readyReceiverStreamAddresses.remove(address);
    }
    await _service.disconnectFrom(address);
  }

  void _handleStatus(ConnectionStatus status) {
    final previous = _lastNotifiedConnectionStatus;
    connectionStatus.value = status;
    if (status == ConnectionStatus.connecting ||
        status == ConnectionStatus.connected) {
      unawaited(BackgroundConnectionService.start());
    }
    if (previous == status) return;
    _lastNotifiedConnectionStatus = status;
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
    if (_startingSystemAudio) return;
    _startingSystemAudio = true;
    try {
      await _startSystemAudioStream();
    } finally {
      _startingSystemAudio = false;
    }
  }

  Future<void> _startSystemAudioStream() async {
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
    _streamingReceiverAddresses
      ..clear()
      ..addAll(addresses);
    _readyReceiverStreamAddresses
      ..clear()
      ..addAll(addresses);
    await audioService.selectCodec(codecPreference.value);
    final pairingText = _pairingInputFor(addresses);
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
    final nativeEligible =
        Platform.isAndroid &&
        !pairingText.contains('=') &&
        (audioService.activeCodecType == AudioCodecType.pcm16 ||
            audioService.activeCodecType == AudioCodecType.opus);
    var nativeStarted = false;
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
        nativeStarted = true;
        audioStatus.value = AudioStreamStatus.streaming;
      } catch (_) {
        // Native capture/Opus is optional. The Dart path remains the
        // compatibility fallback for devices without the native bridge.
        _nativeHostActive = false;
      }
    }
    final commandArguments = <String>[
      _streamSessionId,
      '0',
      audioService.activeCodecType.name,
      if (nativeStarted) 'native' else latencyMode.value.name,
      if (nativeStarted) latencyMode.value.name,
    ];
    if (!nativeStarted) {
      await audioService.startStreaming(ipAddresses: addresses, port: port);
    }
    if (!nativeStarted && !audioService.isStreaming) {
      await _sendControlCommand(addresses, ControlCommandType.streamStop, [
        _streamSessionId,
      ]);
      receiverCount.value = 0;
      _streamingReceiverAddresses.clear();
      _readyReceiverStreamAddresses.clear();
      return;
    }
    // MediaProjection permission is requested inside startStreaming. Notify
    // Receivers only after capture succeeds, so cancelling the Android dialog
    // cannot leave a prepared receiver or show a remote codec snackbar.
    await _sendControlCommand(
      addresses,
      ControlCommandType.streamPrepare,
      commandArguments,
    );
    _startStats();
    await _sendControlCommand(
      addresses,
      ControlCommandType.streamStart,
      commandArguments,
    );
    _ensureDiagnosticTimer();
    unawaited(_updateMediaNotification());
  }

  Future<void> _handleNotificationAction(String action) async {
    switch (action) {
      case 'start':
        await startSystemAudioStream();
      case 'stop':
        await stopSystemAudioStream();
      case 'mute':
        await toggleMasterMute();
      case 'volume_up':
        await adjustMasterVolume(0.1);
      case 'volume_down':
        await adjustMasterVolume(-0.1);
    }
    unawaited(_updateMediaNotification());
  }

  Future<void> toggleMasterMute() async {
    final addresses = _receiverAddresses();
    final shouldMute = !addresses.every(
      (address) => receiverMuted[address] == true,
    );
    for (final address in addresses) {
      receiverMuted[address] = shouldMute;
      await _sendReceiverVolume(
        address,
        shouldMute ? 0 : volumeForReceiver(address),
      );
    }
    receiverMuted.refresh();
  }

  Future<void> adjustMasterVolume(double delta) async {
    for (final address in _receiverAddresses()) {
      final volume = (volumeForReceiver(address) + delta).clamp(0.0, 1.5);
      setReceiverVolume(address, volume);
    }
  }

  Future<void> _updateMediaNotification() => AppNotificationService.showMedia(
    title: 'Sync Audio',
    message: isAudioStreaming ? 'Streaming to Receiver(s)' : 'Ready to stream',
    isPlaying: isAudioStreaming,
    isMuted:
        _receiverAddresses().isNotEmpty &&
        _receiverAddresses().every((address) => receiverMuted[address] == true),
  );

  Future<void> selectCodec(AudioCodecPreference preference) async {
    if (_restartingAudioSettings.value) return;
    final wasStreaming = _audioService?.isStreaming ?? false;
    _restartingAudioSettings.value = wasStreaming;
    try {
      if (wasStreaming) await stopSystemAudioStream();
      codecPreference.value = preference;
      await _audioService?.selectCodec(preference);
      if (wasStreaming) await startSystemAudioStream();
    } finally {
      _restartingAudioSettings.value = false;
    }
  }

  Future<void> configureLatency(LatencyMode mode) async {
    if (_restartingAudioSettings.value) return;
    final wasStreaming = _audioService?.isStreaming ?? false;
    _restartingAudioSettings.value = wasStreaming;
    try {
      if (wasStreaming) await stopSystemAudioStream();
      latencyMode.value = mode;
      await _audioService?.configureLatency(
        mode: mode,
        adaptiveJitter: adaptiveJitter.value,
        driftCorrection: driftCorrection.value,
        maximumDriftCorrectionPpm: maximumDriftCorrectionPpm.value,
      );
      if (wasStreaming) await startSystemAudioStream();
    } finally {
      _restartingAudioSettings.value = false;
    }
  }

  Future<void> _refreshDiagnostics(AudioStreamService audioService) async {
    final now = DateTime.now();
    _receiverDiagnosticsUpdatedAt.removeWhere(
      (id, updatedAt) => now.difference(updatedAt) > const Duration(seconds: 5),
    );
    _receiverDiagnostics.removeWhere(
      (id, _) => !_receiverDiagnosticsUpdatedAt.containsKey(id),
    );
    final local = _nativeHostActive
        ? await _nativeAudioRuntime.diagnostics()
        : audioService.diagnosticsSnapshot;
    final receiverValues = _receiverDiagnostics.values.toList(growable: false);
    if (receiverValues.isEmpty) {
      diagnostics.value = <String, Object>{
        ...local,
        'metricsScope': 'host_sender',
      };
      return;
    }
    diagnostics.value = _aggregateReceiverDiagnostics(receiverValues);
  }

  void _handleControlEvent(ControlEvent event) {
    if (event.command.type != ControlCommandType.bufferStatus ||
        event.command.arguments.length < 7) {
      return;
    }
    final values = event.command.arguments.map(num.tryParse).toList();
    if (values.any((value) => value == null)) return;
    final audioSession = _audioService?.receiverSessions
        .cast<ReceiverSession?>()
        .firstWhere(
          (session) =>
              session?.ipAddress == event.sourceId ||
              session?.id == event.sourceId,
          orElse: () => null,
        );
    _receiverDiagnostics[event.sourceId] = <String, Object>{
      'metricsScope': 'receiver',
      'currentJitterBufferPackets': values[1]!,
      'packetLossPercent': values[2]!,
      'packetUnderrunCount': values[3]!,
      'packetOverrunCount': values[4]!,
      // RTT is measured by the Host's UDP clock-sync exchange. The Receiver
      // reports the other counters, but cannot calculate this value locally.
      'roundTripTimeMicros': audioSession?.roundTripTimeMicros ?? values[5]!,
      'targetJitterBufferMicros': values[6]!,
    };
    _receiverDiagnosticsUpdatedAt[event.sourceId] = DateTime.now();
    unawaited(
      _service.sendControlCommand(
        receiverId: event.sourceId,
        command: ControlCommand(
          type: ControlCommandType.bufferStatus,
          arguments: [
            '0',
            '0',
            '0',
            '0',
            '0',
            '${audioSession?.roundTripTimeMicros ?? values[5]}',
            '0',
          ],
        ),
      ),
    );
    unawaited(_refreshDiagnosticsIfStreaming());
  }

  Future<void> _refreshDiagnosticsIfStreaming() async {
    final audioService = _audioService;
    if (audioService != null && audioService.isStreaming) {
      await _refreshDiagnostics(audioService);
    }
  }

  Map<String, Object> _aggregateReceiverDiagnostics(
    List<Map<String, Object>> values,
  ) {
    num maximum(String key) => values
        .map((value) => value[key] as num? ?? 0)
        .fold<num>(0, (max, value) => value > max ? value : max);
    num average(String key) =>
        values
            .map((value) => value[key] as num? ?? 0)
            .fold<num>(0, (sum, value) => sum + value) /
        values.length;
    return <String, Object>{
      'metricsScope': 'receiver',
      'receiverCount': values.length,
      'currentJitterBufferPackets': average(
        'currentJitterBufferPackets',
      ).round(),
      'packetLossPercent': maximum('packetLossPercent'),
      'packetUnderrunCount': maximum('packetUnderrunCount').round(),
      'packetOverrunCount': maximum('packetOverrunCount').round(),
      'roundTripTimeMicros': maximum('roundTripTimeMicros').round(),
      'targetJitterBufferMicros': maximum('targetJitterBufferMicros').round(),
    };
  }

  Future<void> stopSystemAudioStream() async {
    errorMessage.value = null;
    _stopStats();
    _cleanupDiagnosticTimer();
    _receiverDiagnostics.clear();
    _receiverDiagnosticsUpdatedAt.clear();
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
    audioStatus.value = AudioStreamStatus.stopped;
    receiverCount.value = 0;
    _streamingReceiverAddresses.clear();
    _readyReceiverStreamAddresses.clear();
    receiverSessions.clear();
    unawaited(_updateMediaNotification());
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
    unawaited(_resolveReceiverName(address));
  }

  Future<void> _resolveReceiverName(String address) async {
    try {
      final devices = await _discoveryService.discover();
      for (final device in devices) {
        if (device.ipAddress == address && device.name.trim().isNotEmpty) {
          discoveredDeviceNames[address] = device.name.trim();
          return;
        }
      }
    } catch (_) {
      // Manual setup still works when UDP discovery is unavailable.
    }
  }

  void removeReceiverIp(String address) {
    configuredReceiverIps.remove(address);
    discoveredDeviceNames.remove(address);
    discoveredDeviceLatencyMs.remove(address);
    receiverPairingControllers.remove(address)?.dispose();
  }

  /// Applies the Receiver QR payload: IP address:port:pairing code.
  bool addReceiverFromQrData(String rawData) {
    final parts = rawData.trim().split(':');
    if (parts.length < 3 || parts.length > 4) {
      _showError('Invalid Receiver QR code.');
      return false;
    }
    final address = parts[0].trim();
    final port = int.tryParse(parts[1].trim());
    final pairingCode = parts[2].trim();
    final deviceName = parts.length == 4
        ? Uri.decodeComponent(parts[3].trim())
        : '';
    final parsedIp = InternetAddress.tryParse(address);
    if (parsedIp == null || parsedIp.type != InternetAddressType.IPv4) {
      _showError('QR code contains an invalid Receiver IP address.');
      return false;
    }
    if (port == null || port < 1 || port > 65535) {
      _showError('QR code contains an invalid Receiver port.');
      return false;
    }
    if (!RegExp(r'^\d{8}$').hasMatch(pairingCode)) {
      _showError('QR code contains an invalid pairing code.');
      return false;
    }
    if (port != controlPort) {
      _showError('This Receiver uses control port $controlPort.');
      return false;
    }
    pairingTokenController.text = pairingCode;
    if (!configuredReceiverIps.contains(address)) {
      configuredReceiverIps.add(address);
    }
    receiverPairingControllers[address] ??= TextEditingController();
    receiverPairingControllers[address]!.text = pairingCode;
    if (deviceName.isNotEmpty) {
      discoveredDeviceNames[address] = deviceName;
    } else {
      // Keep older QR codes (without a name field) working as well.
      unawaited(_resolveReceiverName(address));
    }
    errorMessage.value = null;
    return true;
  }

  Future<void> discoverReceivers() async {
    if (_discoveryInProgress) return;
    _discoveryInProgress = true;
    if (_showDiscoveryBusyIndicator) {
      isDiscoveringReceivers.value = true;
    }
    try {
      final devices = await _discoveryService.discover();
      final localAddresses = await _localIpv4Addresses();
      final visibleDevices = devices
          .where((device) => !localAddresses.contains(device.ipAddress))
          .toList(growable: false);
      discoveredDevices.assignAll(visibleDevices);
      final visibleAddresses = visibleDevices
          .map((device) => device.ipAddress)
          .toSet();
      discoveredDeviceNames.removeWhere(
        (address, _) => !visibleAddresses.contains(address),
      );
      discoveredDeviceLatencyMs.removeWhere(
        (address, _) => !visibleAddresses.contains(address),
      );
      for (final address
          in configuredReceiverIps.where(localAddresses.contains).toList()) {
        configuredReceiverIps.remove(address);
        receiverPairingControllers.remove(address)?.dispose();
      }
      for (final device in visibleDevices) {
        // A UDP discovery response can contain the request sender's address
        // on some Android/network stacks. Never show the Host itself as a
        // Receiver, even if the responder returned a wrong address.
        discoveredDeviceNames[device.ipAddress] = device.name;
        discoveredDeviceLatencyMs[device.ipAddress] = device.latencyMs;
        if (!configuredReceiverIps.contains(device.ipAddress)) {
          configuredReceiverIps.add(device.ipAddress);
          receiverPairingControllers[device.ipAddress] =
              TextEditingController();
        }
        final pairingCode = device.pairingCode;
        if (pairingCode != null && RegExp(r'^\d{8}$').hasMatch(pairingCode)) {
          receiverPairingControllers[device.ipAddress]?.text = pairingCode;
        }
      }
      discoveryStatus.value = visibleDevices.isEmpty
          ? (isDiscoveryPolling.value
                ? 'Searching for Receivers…'
                : 'Search stopped.')
          : '${visibleDevices.length} Receiver${visibleDevices.length == 1 ? '' : 's'} found';
    } catch (_) {
      // Discovery is best-effort. A blocked broadcast must not show a false
      // error snackbar or interrupt manual/QR setup.
      discoveryStatus.value = isDiscoveryPolling.value
          ? 'Searching for Receivers…'
          : 'Search stopped.';
    } finally {
      _discoveryInProgress = false;
      if (_showDiscoveryBusyIndicator) {
        isDiscoveringReceivers.value = false;
      }
    }
  }

  Future<Set<String>> _localIpv4Addresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return interfaces
          .expand((interface) => interface.addresses)
          .map((address) => address.address)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Future<void> adjustReceiverCalibration(
    ReceiverSession session,
    int deltaMilliseconds,
  ) async {
    final audioService = _audioService;
    final calibrationMicros =
        session.playbackCalibrationMicros + deltaMilliseconds * 1000;
    // Update the control session immediately so the card reflects the button
    // press even while the UDP/control commands are in flight.
    final controlIndex = receiverSessions.indexWhere(
      (item) =>
          item.ipAddress == session.ipAddress && item.id == item.ipAddress,
    );
    if (controlIndex != -1) {
      receiverSessions[controlIndex] = receiverSessions[controlIndex].copyWith(
        playbackCalibrationMicros: calibrationMicros,
      );
      receiverSessions.refresh();
    }
    final audioSession =
        (audioService?.receiverSessions ?? const <ReceiverSession>[])
            .cast<ReceiverSession?>()
            .firstWhere(
              (candidate) => candidate?.ipAddress == session.ipAddress,
              orElse: () => null,
            );
    if (audioService != null) {
      await audioService.setReceiverCalibration(
        receiverId: audioSession?.id ?? session.id,
        calibrationMicros: calibrationMicros,
      );
    }
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
      roundTripTimeMicros: audio.roundTripTimeMicros,
      lastSyncMicros: audio.lastSyncMicros,
    );
  }

  void _updateSession(ReceiverSession session) {
    final name = session.deviceName?.trim();
    if (name != null && name.isNotEmpty) {
      discoveredDeviceNames[session.ipAddress] = name;
    }
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
    if (session.id == session.ipAddress &&
        session.controlStatus == ControlConnectionStatus.connected) {
      unawaited(_autoStartForConnectedReceivers());
    } else if (session.id == session.ipAddress) {
      _readyReceiverStreamAddresses.remove(session.ipAddress);
    }
  }

  Future<void> _autoStartForConnectedReceivers() async {
    if (_autoStreamInProgress) return;
    if (_nativeHostActive) {
      final addresses = _receiverAddresses();
      final additions = addresses
          .where((address) => !_streamingReceiverAddresses.contains(address))
          .toList(growable: false);
      final reconnects = addresses
          .where((address) => !_readyReceiverStreamAddresses.contains(address))
          .toList(growable: false);
      if (additions.isEmpty && reconnects.isEmpty) return;
      _autoStreamInProgress = true;
      try {
        await _addReceiversToActiveNativeStream(
          additions,
          reconnects: reconnects,
        );
      } finally {
        _autoStreamInProgress = false;
      }
      return;
    }
    final audioService = _audioService;
    if (audioService == null) return;
    final addresses = _receiverAddresses();
    if (addresses.isEmpty) return;

    if (audioService.isStreaming) {
      final known = audioService.receiverSessions
          .map((session) => session.ipAddress)
          .toSet();
      _streamingReceiverAddresses.addAll(known);
      final additions = addresses
          .where((address) => !_streamingReceiverAddresses.contains(address))
          .toList(growable: false);
      final reconnects = addresses
          .where((address) => !_readyReceiverStreamAddresses.contains(address))
          .toList(growable: false);
      if (additions.isEmpty && reconnects.isEmpty) return;
      _autoStreamInProgress = true;
      try {
        await _addReceiversToActiveStream(additions, reconnects: reconnects);
      } finally {
        _autoStreamInProgress = false;
      }
      return;
    }

    final allConnected = addresses.every(
      (address) => receiverSessions.any(
        (session) =>
            session.id == address &&
            session.controlStatus == ControlConnectionStatus.connected,
      ),
    );
    if (!allConnected) return;

    _autoStreamInProgress = true;
    try {
      await startSystemAudioStream();
    } finally {
      _autoStreamInProgress = false;
      unawaited(_autoStartForConnectedReceivers());
    }
  }

  Future<void> _addReceiversToActiveStream(
    List<String> additions, {
    required List<String> reconnects,
  }) async {
    final audioService = _audioService;
    if (audioService == null || !audioService.isStreaming) return;
    final port = int.tryParse(audioPortController.text.trim());
    if (port == null || port < 1 || port > 65535) return;

    await audioService.addReceivers(ipAddresses: additions, port: port);
    final addresses = {...additions, ...reconnects}.toList(growable: false);
    if (addresses.isEmpty) return;
    final commandArguments = <String>[
      _streamSessionId,
      '0',
      audioService.activeCodecType.name,
      latencyMode.value.name,
    ];
    await _sendControlCommand(
      addresses,
      ControlCommandType.streamPrepare,
      commandArguments,
    );
    await _sendControlCommand(
      addresses,
      ControlCommandType.streamStart,
      commandArguments,
    );
    _streamingReceiverAddresses.addAll(addresses);
    _readyReceiverStreamAddresses.addAll(addresses);
    receiverCount.value = _streamingReceiverAddresses.length;
  }

  Future<void> _addReceiversToActiveNativeStream(
    List<String> additions, {
    required List<String> reconnects,
  }) async {
    if (!_nativeHostActive) return;
    if (additions.isNotEmpty) {
      await _nativeAudioRuntime.addNativeHostReceivers(additions);
    }
    final addresses = {...additions, ...reconnects}.toList(growable: false);
    if (addresses.isEmpty) return;
    final commandArguments = <String>[
      _streamSessionId,
      '0',
      _audioService?.activeCodecType.name ?? AudioCodecType.pcm16.name,
      'native',
      latencyMode.value.name,
    ];
    await _sendControlCommand(
      addresses,
      ControlCommandType.streamPrepare,
      commandArguments,
    );
    await _sendControlCommand(
      addresses,
      ControlCommandType.streamStart,
      commandArguments,
    );
    _streamingReceiverAddresses.addAll(addresses);
    _readyReceiverStreamAddresses.addAll(addresses);
    receiverCount.value = _streamingReceiverAddresses.length;
  }

  void _showError(String message) => errorMessage.value = message;

  @override
  void onClose() {
    _statusSubscription.cancel();
    _audioStatusSubscription?.cancel();
    _audioErrorSubscription?.cancel();
    _sessionSubscription?.cancel();
    _notificationActionSubscription?.cancel();
    _diagnosticsSubscription.cancel();
    _diagnosticTimer?.cancel();
    stopDiscoveryPolling();
    if (Get.isRegistered<ScheduledStreamingService>()) {
      Get.find<ScheduledStreamingService>().stop();
    }
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
