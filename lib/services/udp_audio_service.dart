import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../models/audio_stream_status.dart';
import '../models/receiver_session.dart';
import 'audio_capture_service.dart';
import 'audio_codec.dart';
import 'audio_packet_codec.dart';
import 'audio_playback_service.dart';
import 'adaptive_jitter_buffer.dart';
import 'latency_metrics.dart';
import 'secure_transport.dart';

abstract class AudioStreamService {
  Stream<AudioStreamStatus> get statusChanges;

  Stream<String> get errors;

  Stream<ReceiverSession> get sessionChanges;

  AudioStreamStatus get status;

  bool get isStreaming;

  bool get isReceiving;

  List<ReceiverSession> get receiverSessions;

  int get bufferedPackets;

  int get bufferedDurationMicros;

  int get droppedPacketCount;

  LatencyMetricsSnapshot get latencyMetrics;

  Map<String, Object> get diagnosticsSnapshot;

  LatencyMode get latencyMode;

  bool get adaptiveJitterEnabled;

  bool get driftCorrectionEnabled;

  int get maximumDriftCorrectionPpm;

  Future<void> startStreaming({
    required List<String> ipAddresses,
    required int port,
  });

  Future<void> addReceivers({
    required List<String> ipAddresses,
    required int port,
  });

  Future<void> removeReceiver({required String ipAddress});

  Future<void> stopStreaming();

  Future<void> startReceiver({required int port});

  Future<void> stopReceiver();

  Future<void> setReceiverCalibration({
    required String receiverId,
    required int calibrationMicros,
  });

  Future<void> applyPlaybackOffset(int offsetMicros);

  Future<void> setPlaybackVolume(double volume);

  Future<void> selectCodec(AudioCodecPreference preference);

  Future<void> configureLatency({
    required LatencyMode mode,
    required bool adaptiveJitter,
    required bool driftCorrection,
    required int maximumDriftCorrectionPpm,
  });

  AudioCodecType get activeCodecType;

  bool get encryptionEnabled;

  Future<void> setSessionSecurity({
    required String pairingToken,
    required String sessionId,
  });
}

class UdpAudioService implements AudioStreamService {
  UdpAudioService({
    required this.playbackService,
    required this.captureService,
    AudioEncoder? encoder,
    AudioDecoder? decoder,
    this.jitterBuffer = const Duration(milliseconds: 120),
    this.syncInterval = const Duration(seconds: 1),
  }) : encoder = encoder ?? Pcm16AudioEncoder(),
       decoder = decoder ?? Pcm16AudioDecoder();

  final AudioPlaybackService playbackService;
  final AudioCaptureService captureService;
  AudioEncoder encoder;
  AudioDecoder decoder;
  final Duration jitterBuffer;
  final Duration syncInterval;
  LatencyMode _latencyMode = LatencyMode.stable;
  bool _adaptiveJitterEnabled = true;
  bool _driftCorrectionEnabled = true;
  int _maximumDriftCorrectionPpm = 200;
  final _metrics = LatencyMetricsTracker();
  final _jitter = AdaptiveJitterBuffer(mode: LatencyMode.stable);
  final _statusController = StreamController<AudioStreamStatus>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final _sessionController = StreamController<ReceiverSession>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  StreamSubscription<Uint8List>? _captureSubscription;
  Timer? _playbackTimer;
  Timer? _receiverWatchdogTimer;
  Timer? _clockSyncTimer;
  Future<void> _playbackQueue = Future<void>.value();
  int _playbackQueueDepth = 0;
  int _receiverGeneration = 0;
  int _streamGeneration = 0;
  int _lastAudioPacketMicros = 0;
  bool _receiverSilenceNotified = false;
  Future<void> _encodeQueue = Future<void>.value();
  int _encodeQueueDepth = 0;
  static const _maxEncodeQueueDepth = 8;
  Uint8List _pendingEncoderPcm = Uint8List(0);
  AudioStreamStatus _status = AudioStreamStatus.idle;
  bool _streaming = false;
  bool _receiving = false;
  List<InternetAddress> _destinations = const [];
  final Map<String, ReceiverSession> _sessions = <String, ReceiverSession>{};
  // The lowest observed RTT is the least affected by Wi-Fi queueing. Keep it
  // per receiver so clock-offset samples use the cleanest network path.
  final Map<String, int> _bestRoundTripMicros = <String, int>{};
  final Map<int, _ClockRequest> _clockRequests = <int, _ClockRequest>{};
  int _destinationPort = 0;
  int _packetSequence = 0;
  int _clockSequence = 0;
  Stopwatch? _streamClock;
  final Stopwatch _receiverClock = Stopwatch();
  int _droppedPackets = 0;
  int _totalBytesSent = 0;
  SecretKey? _sessionKey;
  String? _securitySessionId;
  final _sessionKeyService = SessionKeyService();
  // Audio sequence numbers restart for every stream. Keep replay protection
  // scoped to the active stream instead of the lifetime of this service.
  ReplayGuard _replayGuard = ReplayGuard();
  int _hostToLocalOffsetMicros = 0;
  bool _clockSynchronized = false;
  int _driftCorrectionPpm = 0;
  int _lastDriftUpdateMicros = 0;
  double _playbackVolume = 1.0;
  final bool _autoLatencyEnabled = true;
  int _consecutiveUnderruns = 0;

  @override
  Stream<AudioStreamStatus> get statusChanges => _statusController.stream;

  @override
  Stream<String> get errors => _errorsController.stream;

  @override
  Stream<ReceiverSession> get sessionChanges => _sessionController.stream;

  @override
  AudioStreamStatus get status => _status;

  @override
  bool get isStreaming => _streaming;

  @override
  bool get isReceiving => _receiving;

  @override
  List<ReceiverSession> get receiverSessions =>
      List.unmodifiable(_sessions.values);

  @override
  int get bufferedPackets => _jitter.length;

  @override
  int get bufferedDurationMicros {
    return _jitter.bufferedDurationMicros;
  }

  @override
  int get droppedPacketCount => _droppedPackets;

  @override
  LatencyMetricsSnapshot get latencyMetrics => _metrics.snapshot();

  @override
  Map<String, Object> get diagnosticsSnapshot {
    final map = latencyMetrics.toRedactedMap();
    map['totalBytesSent'] = _totalBytesSent;
    return map;
  }

  @override
  LatencyMode get latencyMode => _latencyMode;

  @override
  bool get adaptiveJitterEnabled => _adaptiveJitterEnabled;

  @override
  bool get driftCorrectionEnabled => _driftCorrectionEnabled;

  @override
  int get maximumDriftCorrectionPpm => _maximumDriftCorrectionPpm;

  @override
  AudioCodecType get activeCodecType => encoder.codecType;

  @override
  bool get encryptionEnabled => _sessionKey != null;

  @override
  Future<void> setSessionSecurity({
    required String pairingToken,
    required String sessionId,
  }) async {
    _sessionKey = await _sessionKeyService.derive(
      pairingToken: pairingToken,
      sessionId: sessionId,
    );
    _securitySessionId = sessionId;
    // A new STREAM_PREPARE marks a new audio session. The Host resets its
    // packet sequence at every start, so old nonces must not be rejected in
    // the new session.
    _replayGuard = ReplayGuard();
  }

  @override
  Future<void> selectCodec(AudioCodecPreference preference) async {
    if (_streaming || _receiving) {
      _emitError('Stop the current audio stream before changing codec.');
      return;
    }
    // Auto stays on PCM until both peers have explicitly negotiated Opus.
    // This keeps mixed-version devices compatible while retaining an explicit
    // Opus opt-in for installations where both sides are known to support it.
    final useOpus = preference == AudioCodecPreference.opus;
    if (useOpus && OpusRuntime.isAvailable) {
      try {
        encoder = NativeOpusAudioEncoder();
        decoder = NativeOpusAudioDecoder();
        return;
      } catch (_) {
        if (preference == AudioCodecPreference.opus) {
          _emitError('Opus is unavailable; falling back to PCM.');
        }
      }
    }
    encoder = Pcm16AudioEncoder();
    decoder = Pcm16AudioDecoder();
  }

  @override
  Future<void> configureLatency({
    required LatencyMode mode,
    required bool adaptiveJitter,
    required bool driftCorrection,
    required int maximumDriftCorrectionPpm,
  }) async {
    if (_streaming || _receiving) {
      _emitError(
        'Stop the current audio stream before changing latency settings.',
      );
      return;
    }
    _latencyMode = mode;
    _adaptiveJitterEnabled = adaptiveJitter;
    _driftCorrectionEnabled = driftCorrection;
    _maximumDriftCorrectionPpm = maximumDriftCorrectionPpm.clamp(0, 300);
    _jitter.configure(mode: mode, enabled: adaptiveJitter);
  }

  @override
  Future<void> startStreaming({
    required List<String> ipAddresses,
    required int port,
  }) async {
    if (_streaming) {
      _emitError('System audio streaming is already running.');
      return;
    }
    if (ipAddresses.isEmpty) {
      _emitError('Add at least one receiver IP address.');
      _setStatus(AudioStreamStatus.error);
      return;
    }
    _setStatus(AudioStreamStatus.starting);
    try {
      _destinations = ipAddresses
          .map(InternetAddress.new)
          .toList(growable: false);
      _destinationPort = port;
      _packetSequence = 0;
      _clockSequence = 0;
      _bestRoundTripMicros.clear();
      _droppedPackets = 0;
      _totalBytesSent = 0;
      _pendingEncoderPcm = Uint8List(0);
      _jitter.reset();
      await encoder.reset();
      _streamClock = Stopwatch()..start();
      final activeIds = <String>{};
      for (final address in _destinations) {
        final id = _sessionId(address.address, port);
        activeIds.add(id);
        final session =
            (_sessions[id] ??
                    ReceiverSession(
                      id: id,
                      ipAddress: address.address,
                      port: port,
                    ))
                .copyWith(
                  ipAddress: address.address,
                  port: port,
                  status: ReceiverSessionStatus.synchronizing,
                );
        _updateSession(session);
      }
      _sessions.removeWhere((id, _) => !activeIds.contains(id));
      _socket?.close();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSubscription = _socket!.listen(_handleHostSocketEvent);
      _streaming = true;
      final streamGeneration = ++_streamGeneration;
      _clockSyncTimer = Timer.periodic(
        syncInterval,
        (_) => _synchronizeReceivers(),
      );
      _synchronizeReceivers();
      _captureSubscription = captureService.pcmChunks.listen(
        (pcm) => _sendPcmPacket(pcm, streamGeneration),
        onError: (Object error) => unawaited(_handleCaptureError(error)),
      );
      await captureService.start();
      _setStatus(AudioStreamStatus.streaming);
    } on SocketException {
      await stopStreaming();
      _emitError(
        'Could not open the audio port. Check your network connection.',
      );
      _setStatus(AudioStreamStatus.error);
    } on PlatformException catch (error) {
      await stopStreaming();
      final message = switch (error.code) {
        'MEDIA_PROJECTION_DENIED' =>
          'Permission not granted. Tap "Start" again and accept the screen recording dialog to share audio.',
        'MICROPHONE_PERMISSION_DENIED' =>
          'Microphone access was not allowed. Tap "Start" again and accept the permission to share audio.',
        'SYSTEM_AUDIO_UNSUPPORTED' =>
          'This Android version is too old. Audio sharing needs Android 10 or higher.',
        'SYSTEM_AUDIO_START_FAILED' =>
          'Could not start audio sharing. ${error.message}. Please try again.',
        _ =>
          'Could not start audio sharing. ${error.message}. Please try again.',
      };
      _emitError(message);
      _setStatus(AudioStreamStatus.error);
    } catch (error) {
      await stopStreaming();
      _emitError('Could not start audio sharing. Please try again.');
      _setStatus(AudioStreamStatus.error);
    }
  }

  @override
  Future<void> addReceivers({
    required List<String> ipAddresses,
    required int port,
  }) async {
    if (!_streaming || ipAddresses.isEmpty) return;
    final existing = _destinations.map((address) => address.address).toSet();
    final additions = ipAddresses
        .where((address) => !existing.contains(address))
        .map(InternetAddress.new)
        .toList(growable: false);
    if (additions.isEmpty) return;

    _destinations = [..._destinations, ...additions];
    for (final address in additions) {
      final id = _sessionId(address.address, port);
      _updateSession(
        ReceiverSession(
          id: id,
          ipAddress: address.address,
          port: port,
          status: ReceiverSessionStatus.synchronizing,
        ),
      );
    }
    _synchronizeReceivers();
  }

  @override
  Future<void> removeReceiver({required String ipAddress}) async {
    if (!_streaming) return;
    _destinations = _destinations
        .where((address) => address.address != ipAddress)
        .toList(growable: false);
    final sessionIds = _sessions.keys
        .where((id) => id.startsWith('$ipAddress:'))
        .toList(growable: false);
    for (final id in sessionIds) {
      _sessions.remove(id);
    }
    if (_destinations.isEmpty) {
      await stopStreaming();
      return;
    }
  }

  void _synchronizeReceivers() {
    final socket = _socket;
    final clock = _streamClock;
    if (!_streaming || socket == null || clock == null) return;
    final now = clock.elapsedMicroseconds;
    for (final destination in _destinations) {
      final id = _sessionId(destination.address, _destinationPort);
      final session = _sessions[id];
      if (session == null) continue;
      final requestId = _clockSequence++;
      _clockRequests[requestId] = _ClockRequest(
        sessionId: id,
        sentAtMicros: now,
      );
      if (_clockRequests.length > 128) {
        final cutoff = now - syncInterval.inMicroseconds * 5;
        _clockRequests.removeWhere((_, r) => r.sentAtMicros < cutoff);
      }
      socket.send(
        AudioPacketCodec.encode(
          type: AudioPacketType.clockSyncRequest,
          sequence: requestId,
          timestampMicros: now,
        ),
        destination,
        _destinationPort,
      );
      if (session.lastSyncMicros != null &&
          now - session.lastSyncMicros! > syncInterval.inMicroseconds * 3) {
        _updateSession(
          session.copyWith(
            status: ReceiverSessionStatus.reconnecting,
            reconnectAttempt: session.reconnectAttempt + 1,
          ),
        );
      }
    }
  }

  void _handleHostSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      final packet = AudioPacketCodec.decode(datagram!.data);
      if (packet?.type != AudioPacketType.clockSyncResponse) continue;
      final request = _clockRequests.remove(packet!.sequence);
      if (request == null || _streamClock == null) continue;
      final receivedAt = _streamClock!.elapsedMicroseconds;
      final session = _sessions[request.sessionId];
      if (session == null) continue;
      final roundTripTime = receivedAt - request.sentAtMicros;
      final sampleOffset =
          ((packet.timestampMicros - request.sentAtMicros) +
              (packet.timestampMicros - receivedAt)) ~/
          2;
      final bestRoundTrip = _bestRoundTripMicros[request.sessionId];
      final isNewBest = bestRoundTrip == null || roundTripTime < bestRoundTrip;
      if (isNewBest) {
        _bestRoundTripMicros[request.sessionId] = roundTripTime;
      }
      final comparisonRoundTrip = bestRoundTrip ?? roundTripTime;
      // Prefer a new minimum-RTT sample. Heavily queued samples are still
      // useful, but only with a small weight so they do not move every
      // receiver's playback clock audibly on a busy Wi-Fi network.
      final alpha = session.lastSyncMicros == null
          ? 1.0
          : isNewBest
          ? 0.65
          : roundTripTime <= comparisonRoundTrip + 2000
          ? 0.25
          : 0.06;
      final filteredOffset =
          session.clockOffsetMicros +
          ((sampleOffset - session.clockOffsetMicros) * alpha).round();
      final elapsed = session.lastSyncMicros == null
          ? 0
          : receivedAt - session.lastSyncMicros!;
      final driftPpm = elapsed <= 0
          ? session.clockDriftPpm
          : (((filteredOffset - session.clockOffsetMicros) * 1000000) / elapsed)
                .round();
      final updated = session.copyWith(
        status: ReceiverSessionStatus.connected,
        clockOffsetMicros: filteredOffset,
        clockDriftPpm: driftPpm.clamp(-5000, 5000),
        roundTripTimeMicros: roundTripTime,
        lastSyncMicros: receivedAt,
        reconnectAttempt: 0,
      );
      _updateSession(updated);
      _metrics.clockSample(
        rttMicros: roundTripTime,
        offsetMicros: filteredOffset,
      );
      final appliedDrift = _driftCorrectionEnabled
          ? driftPpm.clamp(
              -_maximumDriftCorrectionPpm,
              _maximumDriftCorrectionPpm,
            )
          : 0;
      _metrics.setDrift(estimatedPpm: driftPpm, appliedPpm: appliedDrift);
      _sendClockOffset(updated, packet.sequence);
      _sendClockDrift(updated, packet.sequence, appliedDrift);
    }
  }

  Future<void> _handleCaptureError(Object error) async {
    await stopStreaming();
    _emitError('Audio sharing stopped unexpectedly. Please try again.');
    _setStatus(AudioStreamStatus.error);
  }

  void _sendPcmPacket(Uint8List pcm, int generation) {
    if (!_streaming || generation != _streamGeneration) return;
    _metrics.captureStarted();
    if (encoder.codecType == AudioCodecType.pcm16) {
      // Preserve normal capture buffers, but split unusually large macOS
      // buffers before they reach the UDP socket. 2048 bytes plus the packet
      // header remains within the supported datagram size on the target LAN.
      const maxPcmPayload = 2048;
      if (pcm.length <= maxPcmPayload) {
        _enqueuePcmFrame(pcm, generation);
        return;
      }
      final frameBytes = encoder.config.frameBytes;
      for (var offset = 0; offset < pcm.length; offset += frameBytes) {
        final end = (offset + frameBytes).clamp(0, pcm.length);
        _enqueuePcmFrame(
          Uint8List.fromList(pcm.sublist(offset, end)),
          generation,
        );
      }
      return;
    }
    // Keep every UDP datagram at one negotiated audio frame. This is
    // important on macOS where BlackHole may deliver a larger audio buffer;
    // a 3840-byte PCM payload exceeds the usual Wi-Fi MTU and causes
    // EMSGSIZE/"Message too long" from RawDatagramSocket.
    final combined = Uint8List(_pendingEncoderPcm.length + pcm.length)
      ..setRange(0, _pendingEncoderPcm.length, _pendingEncoderPcm)
      ..setRange(
        _pendingEncoderPcm.length,
        _pendingEncoderPcm.length + pcm.length,
        pcm,
      );
    final frameBytes = encoder.config.frameBytes;
    var offset = 0;
    while (combined.length - offset >= frameBytes) {
      _enqueuePcmFrame(
        Uint8List.fromList(combined.sublist(offset, offset + frameBytes)),
        generation,
      );
      offset += frameBytes;
    }
    _pendingEncoderPcm = Uint8List.fromList(combined.sublist(offset));
  }

  void _enqueuePcmFrame(Uint8List pcm, int generation) {
    if (!_streaming || generation != _streamGeneration) return;
    if (_encodeQueueDepth >= _maxEncodeQueueDepth) {
      _emitError('Audio encoder is behind; dropping a capture frame.');
      return;
    }
    _encodeQueueDepth++;
    _encodeQueue = _encodeQueue
        .then((_) async {
          try {
            await _encodeAndSendPcm(pcm, generation);
          } catch (_) {
            await _handleEncodingError();
          }
        })
        .whenComplete(() => _encodeQueueDepth--);
  }

  Future<void> _handleEncodingError() async {
    if (!_streaming) return;
    if (encoder.codecType == AudioCodecType.opus) {
      encoder = Pcm16AudioEncoder();
      _emitError('Opus encoding failed — auto-switched to PCM.');
      return;
    }
    await stopStreaming();
    _emitError('Audio encoding failed. Stream stopped.');
    _setStatus(AudioStreamStatus.error);
  }

  Future<void> _encodeAndSendPcm(Uint8List pcm, int generation) async {
    final socket = _socket;
    final clock = _streamClock;
    if (!_streaming ||
        generation != _streamGeneration ||
        socket == null ||
        clock == null ||
        pcm.isEmpty) {
      return;
    }
    final encodeClock = Stopwatch()..start();
    final encoded = await encoder.encode(pcm);
    _metrics.encoded(encodeClock.elapsed);
    if (!_streaming || generation != _streamGeneration || encoded.isEmpty) {
      return;
    }
    final packet = AudioPacketCodec.encode(
      type: AudioPacketType.pcmAudio,
      sequence: _packetSequence++,
      timestampMicros:
          clock.elapsedMicroseconds +
          LatencyModeConfig.forMode(_latencyMode).normalMicros,
      codecType: encoder.codecType,
      payload: encoded,
    );
    final wirePacket = _sessionKey == null
        ? packet
        : await EncryptedAudioPacketCodec.encrypt(
            packet: packet,
            key: _sessionKey!,
            sessionId: _securitySessionId!,
          );
    for (final destination in _destinations) {
      socket.send(wirePacket, destination, _destinationPort);
      _totalBytesSent += wirePacket.length;
    }
    _metrics.packetSent();
    for (final session in _sessions.values.where(
      (value) => value.status == ReceiverSessionStatus.connected,
    )) {
      _updateSession(session.copyWith(status: ReceiverSessionStatus.streaming));
    }
  }

  @override
  Future<void> stopStreaming() async {
    _streamGeneration++;
    await _captureSubscription?.cancel();
    _captureSubscription = null;
    await captureService.stop();
    _streaming = false;
    _clockSyncTimer?.cancel();
    _clockSyncTimer = null;
    _clockRequests.clear();
    _bestRoundTripMicros.clear();
    _pendingEncoderPcm = Uint8List(0);
    await decoder.reset();
    _streamClock?.stop();
    _streamClock = null;
    _sessionKey = null;
    _securitySessionId = null;
    for (final session in _sessions.values) {
      _emitSession(
        session.copyWith(status: ReceiverSessionStatus.disconnected),
      );
    }
    _sessions.clear();
    _socket?.close();
    _socket = null;
    _setStatus(AudioStreamStatus.stopped);
  }

  @override
  Future<void> setReceiverCalibration({
    required String receiverId,
    required int calibrationMicros,
  }) async {
    final session = _sessions[receiverId];
    if (session == null) return;
    final updated = session.copyWith(
      playbackCalibrationMicros: calibrationMicros,
    );
    _updateSession(updated);
    if (_streaming) {
      _sendClockOffset(updated, _clockSequence++);
    }
  }

  @override
  Future<void> applyPlaybackOffset(int offsetMicros) async {
    if (!_receiving) return;
    _hostToLocalOffsetMicros = offsetMicros;
    _clockSynchronized = true;
  }

  /// Sets the receiver-side gain. This is intentionally applied to the
  /// decoded PCM so it works independently of the Android media volume.
  @override
  Future<void> setPlaybackVolume(double volume) async {
    _playbackVolume = volume.clamp(0.0, 1.5).toDouble();
  }

  void _sendClockOffset(ReceiverSession session, int sequence) {
    final socket = _socket;
    if (socket == null) return;
    socket.send(
      AudioPacketCodec.encode(
        type: AudioPacketType.clockOffset,
        sequence: sequence,
        timestampMicros:
            session.clockOffsetMicros + session.playbackCalibrationMicros,
      ),
      InternetAddress(session.ipAddress),
      session.port,
    );
  }

  void _sendClockDrift(
    ReceiverSession session,
    int sequence,
    int appliedDriftPpm,
  ) {
    final socket = _socket;
    if (socket == null) return;
    socket.send(
      AudioPacketCodec.encode(
        type: AudioPacketType.clockDrift,
        sequence: sequence,
        timestampMicros: appliedDriftPpm,
      ),
      InternetAddress(session.ipAddress),
      session.port,
    );
  }

  @override
  Future<void> startReceiver({required int port}) async {
    if (_receiving) {
      _emitError('The audio receiver is already running.');
      return;
    }
    _setStatus(AudioStreamStatus.starting);
    try {
      await playbackService.start();
      _socket?.close();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _receiving = true;
      _playbackQueue = Future<void>.value();
      _playbackQueueDepth = 0;
      _clockSynchronized = false;
      _hostToLocalOffsetMicros = 0;
      _driftCorrectionPpm = 0;
      _lastDriftUpdateMicros = 0;
      _jitter.reset();
      _receiverClock
        ..reset()
        ..start();
      _playbackTimer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => _drainPlaybackBuffer(),
      );
      _receiverWatchdogTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _checkReceiverHealth(),
      );
      _setStatus(AudioStreamStatus.receiving);
      _udpSubscription = _socket!.listen(_handleReceiverSocketEvent);
    } on SocketException {
      await stopReceiver();
      _emitError('Could not open the audio port. Try restarting the app.');
      _setStatus(AudioStreamStatus.error);
    } catch (error) {
      await stopReceiver();
      _emitError('Could not start audio playback. Please try again.');
      _setStatus(AudioStreamStatus.error);
    }
  }

  void _handleReceiverSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || !_receiving) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      final source = datagram!;
      unawaited(_handleReceiverDatagram(source));
    }
  }

  Future<void> _handleReceiverDatagram(Datagram source) async {
    Uint8List data = source.data;
    _metrics.packetArrived();
    if (EncryptedAudioPacketCodec.isEncrypted(data)) {
      final key = _sessionKey;
      final sessionId = _securitySessionId;
      if (key == null || sessionId == null) return;
      final decryptClock = Stopwatch()..start();
      try {
        data = await EncryptedAudioPacketCodec.decrypt(
          packet: data,
          key: key,
          sessionId: sessionId,
          replayGuard: _replayGuard,
        );
        _metrics.decrypted(decryptClock.elapsed);
      } catch (_) {
        _emitError('Encrypted audio packet rejected.');
        return;
      }
    }
    final packet = AudioPacketCodec.decode(data);
    if (packet == null) return;
    switch (packet.type) {
      case AudioPacketType.clockSyncRequest:
        final socket = _socket;
        if (socket == null || !_receiving) return;
        final now = _receiverClock.elapsedMicroseconds;
        socket.send(
          AudioPacketCodec.encode(
            type: AudioPacketType.clockSyncResponse,
            sequence: packet.sequence,
            timestampMicros: now,
          ),
          source.address,
          source.port,
        );
      case AudioPacketType.clockOffset:
        _hostToLocalOffsetMicros = packet.timestampMicros;
        _clockSynchronized = true;
        _lastDriftUpdateMicros = _receiverClock.elapsedMicroseconds;
      case AudioPacketType.clockDrift:
        _driftCorrectionPpm = packet.timestampMicros.clamp(
          -_maximumDriftCorrectionPpm,
          _maximumDriftCorrectionPpm,
        );
        _metrics.setDrift(
          estimatedPpm: _driftCorrectionPpm,
          appliedPpm: _driftCorrectionPpm,
        );
      case AudioPacketType.pcmAudio:
        if (packet.codecType != decoder.codecType) return;
        final now = _receiverClock.elapsedMicroseconds;
        _lastAudioPacketMicros = now;
        _receiverSilenceNotified = false;
        final correction = _driftCorrectionEnabled
            ? (((now - _lastDriftUpdateMicros) * _driftCorrectionPpm) ~/
                      1000000)
                  .clamp(-20000, 20000)
            : 0;
        final adaptiveDelay = _adaptiveJitterEnabled
            ? _jitter.targetBufferMicros -
                  LatencyModeConfig.forMode(_latencyMode).normalMicros
            : 0;
        _jitter.add(
          JitterAudioPacket(
            sequence: packet.sequence,
            timestampMicros:
                packet.timestampMicros +
                _hostToLocalOffsetMicros +
                correction +
                adaptiveDelay,
            payload: packet.payload,
            arrivalMicros: now,
          ),
        );
        _metrics.setBuffer(
          currentPackets: _jitter.length,
          targetMicros: _jitter.targetBufferMicros,
        );
      case AudioPacketType.clockSyncResponse:
        break;
    }
  }

  void _autoAdjustLatency() {
    if (!_autoLatencyEnabled || !_adaptiveJitterEnabled) return;
    if (_consecutiveUnderruns >= 10 && _latencyMode != LatencyMode.stable) {
      _latencyMode = LatencyMode.stable;
      _jitter.configure(mode: LatencyMode.stable, enabled: true);
      _consecutiveUnderruns = 0;
    }
  }

  void _drainPlaybackBuffer() {
    if (!_receiving || !_clockSynchronized) return;
    final now = _receiverClock.elapsedMicroseconds;
    final packet = _jitter.takeReady(now);
    if (packet == null) {
      _droppedPackets = _jitter.underruns;
      _consecutiveUnderruns++;
      _autoAdjustLatency();
      return;
    }
    _consecutiveUnderruns = 0;
    _autoAdjustLatency();
    _metrics.scheduled(
      timestampMicros: packet.timestampMicros,
      waitingMicros: now - packet.arrivalMicros,
    );
    // Never allow a slow native audio device to create an unbounded Future
    // chain. Once this queue is full, dropping one old frame is preferable to
    // adding hundreds of milliseconds of latency.
    if (_playbackQueueDepth >= 3) {
      _droppedPackets++;
      _metrics.packetOverrun();
      return;
    }
    final generation = _receiverGeneration;
    _playbackQueueDepth++;
    _playbackQueue = _playbackQueue
        .then((_) async {
          if (!_receiving || generation != _receiverGeneration) return;
          final decodeClock = Stopwatch()..start();
          final pcm = await decoder.decode(packet.payload);
          _metrics.decoded(decodeClock.elapsed);
          if (_receiving && generation == _receiverGeneration) {
            await playbackService.writePcm(_applyPlaybackVolume(pcm));
          }
        })
        .catchError((_) {
          _emitError('Audio playback failed on the receiver.');
          _setStatus(AudioStreamStatus.error);
        })
        .whenComplete(() {
          if (generation == _receiverGeneration && _playbackQueueDepth > 0) {
            _playbackQueueDepth--;
          }
        });
  }

  void _checkReceiverHealth() {
    if (!_receiving || _lastAudioPacketMicros == 0) return;
    final silenceMicros =
        _receiverClock.elapsedMicroseconds - _lastAudioPacketMicros;
    if (silenceMicros >= const Duration(seconds: 5).inMicroseconds &&
        !_receiverSilenceNotified) {
      _receiverSilenceNotified = true;
      _emitError(
        'No audio packets received for 5 seconds. Check the Host and Wi-Fi connection.',
      );
    }
  }

  Uint8List _applyPlaybackVolume(Uint8List pcm) {
    final gain = _playbackVolume;
    if (gain == 1.0) return pcm;
    final adjusted = Uint8List.fromList(pcm);
    final data = ByteData.sublistView(adjusted);
    for (var offset = 0; offset + 1 < adjusted.length; offset += 2) {
      final sample = data.getInt16(offset, Endian.little);
      final scaled = (sample * gain).round().clamp(-32768, 32767);
      data.setInt16(offset, scaled, Endian.little);
    }
    return adjusted;
  }

  @override
  Future<void> stopReceiver() async {
    _receiving = false;
    _receiverGeneration++;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _receiverWatchdogTimer?.cancel();
    _receiverWatchdogTimer = null;
    _lastAudioPacketMicros = 0;
    _receiverSilenceNotified = false;
    _jitter.reset();
    _clockSynchronized = false;
    _receiverClock.stop();
    _replayGuard = ReplayGuard();
    await _udpSubscription?.cancel();
    _udpSubscription = null;
    _socket?.close();
    _socket = null;
    await playbackService.stop();
    _setStatus(AudioStreamStatus.stopped);
  }

  void _updateSession(ReceiverSession session) {
    _sessions[session.id] = session;
    _emitSession(session);
  }

  void _emitSession(ReceiverSession session) {
    if (!_sessionController.isClosed) _sessionController.add(session);
  }

  String _sessionId(String ipAddress, int port) => '$ipAddress:$port';

  void _setStatus(AudioStreamStatus value) {
    _status = value;
    if (!_statusController.isClosed) _statusController.add(value);
  }

  void _emitError(String message) {
    if (!_errorsController.isClosed) _errorsController.add(message);
  }

  Future<void> dispose() async {
    await stopStreaming();
    await stopReceiver();
    await _statusController.close();
    await _errorsController.close();
    await _sessionController.close();
  }
}

class _ClockRequest {
  const _ClockRequest({required this.sessionId, required this.sentAtMicros});

  final String sessionId;
  final int sentAtMicros;
}
