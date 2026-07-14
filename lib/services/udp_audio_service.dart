import 'dart:async';
import 'dart:io';

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

  Future<void> stopStreaming();

  Future<void> startReceiver({required int port});

  Future<void> stopReceiver();

  Future<void> setReceiverCalibration({
    required String receiverId,
    required int calibrationMicros,
  });

  Future<void> applyPlaybackOffset(int offsetMicros);

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
    this.syncInterval = const Duration(seconds: 2),
  }) : encoder = encoder ?? Pcm16AudioEncoder(),
       decoder = decoder ?? Pcm16AudioDecoder();

  final AudioPlaybackService playbackService;
  final AudioCaptureService captureService;
  AudioEncoder encoder;
  AudioDecoder decoder;
  final Duration jitterBuffer;
  final Duration syncInterval;
  LatencyMode _latencyMode = LatencyMode.balanced;
  bool _adaptiveJitterEnabled = true;
  bool _driftCorrectionEnabled = true;
  int _maximumDriftCorrectionPpm = 200;
  final _metrics = LatencyMetricsTracker();
  final _jitter = AdaptiveJitterBuffer();
  final _statusController = StreamController<AudioStreamStatus>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  final _sessionController = StreamController<ReceiverSession>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  StreamSubscription<Uint8List>? _captureSubscription;
  Timer? _playbackTimer;
  Timer? _clockSyncTimer;
  Future<void> _playbackQueue = Future<void>.value();
  Future<void> _encodeQueue = Future<void>.value();
  int _encodeQueueDepth = 0;
  static const _maxEncodeQueueDepth = 8;
  Uint8List _pendingEncoderPcm = Uint8List(0);
  AudioStreamStatus _status = AudioStreamStatus.idle;
  bool _streaming = false;
  bool _receiving = false;
  List<InternetAddress> _destinations = const [];
  final Map<String, ReceiverSession> _sessions = <String, ReceiverSession>{};
  final Map<int, _ClockRequest> _clockRequests = <int, _ClockRequest>{};
  int _destinationPort = 0;
  int _packetSequence = 0;
  int _clockSequence = 0;
  Stopwatch? _streamClock;
  final Stopwatch _receiverClock = Stopwatch();
  int _droppedPackets = 0;
  SecretKey? _sessionKey;
  String? _securitySessionId;
  final _sessionKeyService = SessionKeyService();
  final _replayGuard = ReplayGuard();
  int _hostToLocalOffsetMicros = 0;
  bool _clockSynchronized = false;
  int _driftCorrectionPpm = 0;
  int _lastDriftUpdateMicros = 0;
  final bool _autoLatencyEnabled = true;
  int _consecutiveUnderruns = 0;
  int _consecutiveGoodFrames = 0;

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
  Map<String, Object> get diagnosticsSnapshot => latencyMetrics.toRedactedMap();

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
      _droppedPackets = 0;
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
      _clockSyncTimer = Timer.periodic(
        syncInterval,
        (_) => _synchronizeReceivers(),
      );
      _synchronizeReceivers();
      _captureSubscription = captureService.pcmChunks.listen(
        _sendPcmPacket,
        onError: (_) => unawaited(_handleCaptureError()),
      );
      await captureService.start();
      _setStatus(AudioStreamStatus.streaming);
    } on SocketException {
      await stopStreaming();
      _emitError('Unable to start UDP audio. Check the network connection.');
      _setStatus(AudioStreamStatus.error);
    } on PlatformException catch (error) {
      await stopStreaming();
      final message = switch (error.code) {
        'MEDIA_PROJECTION_DENIED' =>
          'System audio capture permission was denied.',
        'MICROPHONE_PERMISSION_DENIED' =>
          'Audio capture permission was denied.',
        'SYSTEM_AUDIO_UNSUPPORTED' =>
          'System audio capture requires Android 10 or newer.',
        _ => 'Unable to start system audio capture.',
      };
      _emitError(message);
      _setStatus(AudioStreamStatus.error);
    } catch (error) {
      await stopStreaming();
      _emitError(
        'Unable to start system audio capture: $error',
      );
      _setStatus(AudioStreamStatus.error);
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
      final alpha = session.lastSyncMicros == null
          ? 1.0
          : (roundTripTime <= session.roundTripTimeMicros ? 0.35 : 0.15);
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

  Future<void> _handleCaptureError() async {
    await stopStreaming();
    _emitError('System audio capture failed.');
    _setStatus(AudioStreamStatus.error);
  }

  void _sendPcmPacket(Uint8List pcm) {
    _metrics.captureStarted();
    if (encoder.codecType == AudioCodecType.opus) {
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
        );
        offset += frameBytes;
      }
      _pendingEncoderPcm = Uint8List.fromList(combined.sublist(offset));
      return;
    }
    _enqueuePcmFrame(pcm);
  }

  void _enqueuePcmFrame(Uint8List pcm) {
    if (_encodeQueueDepth >= _maxEncodeQueueDepth) {
      _emitError('Audio encoder is behind; dropping a capture frame.');
      return;
    }
    _encodeQueueDepth++;
    _encodeQueue = _encodeQueue
        .then((_) async {
          try {
            await _encodeAndSendPcm(pcm);
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

  Future<void> _encodeAndSendPcm(Uint8List pcm) async {
    final socket = _socket;
    final clock = _streamClock;
    if (!_streaming || socket == null || clock == null || pcm.isEmpty) return;
    final encodeClock = Stopwatch()..start();
    final encoded = await encoder.encode(pcm);
    _metrics.encoded(encodeClock.elapsed);
    if (!_streaming || encoded.isEmpty) return;
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
    await _captureSubscription?.cancel();
    _captureSubscription = null;
    await captureService.stop();
    _streaming = false;
    _clockSyncTimer?.cancel();
    _clockSyncTimer = null;
    _clockRequests.clear();
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
      _clockSynchronized = false;
      _hostToLocalOffsetMicros = 0;
      _driftCorrectionPpm = 0;
      _lastDriftUpdateMicros = 0;
      _jitter.reset();
      _receiverClock
        ..reset()
        ..start();
      _playbackTimer = Timer.periodic(
        const Duration(milliseconds: 15),
        (_) => _drainPlaybackBuffer(),
      );
      _setStatus(AudioStreamStatus.receiving);
      _udpSubscription = _socket!.listen(_handleReceiverSocketEvent);
    } on SocketException {
      await stopReceiver();
      _emitError('Unable to start the UDP audio receiver. Port may be in use.');
      _setStatus(AudioStreamStatus.error);
    } catch (error) {
      await stopReceiver();
      _emitError('Unable to initialize Android audio playback: $error');
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
        final correction = _driftCorrectionEnabled
            ? (((now - _lastDriftUpdateMicros) * _driftCorrectionPpm)
                  ~/ 1000000)
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
      _consecutiveGoodFrames = 0;
    } else if (_consecutiveGoodFrames >= 500 && _latencyMode != LatencyMode.ultraLow) {
      _latencyMode = _latencyMode == LatencyMode.stable
          ? LatencyMode.balanced
          : LatencyMode.ultraLow;
      _jitter.configure(mode: _latencyMode, enabled: true);
      _consecutiveGoodFrames = 0;
    }
  }

  void _drainPlaybackBuffer() {
    if (!_receiving || !_clockSynchronized) return;
    final now = _receiverClock.elapsedMicroseconds;
    final packet = _jitter.takeReady(now);
    if (packet == null) {
      _droppedPackets = _jitter.underruns;
      _consecutiveGoodFrames = 0;
      _consecutiveUnderruns++;
      _autoAdjustLatency();
      return;
    }
    _consecutiveUnderruns = 0;
    _consecutiveGoodFrames++;
    _autoAdjustLatency();
    _metrics.scheduled(
      timestampMicros: packet.timestampMicros,
      waitingMicros: now - packet.arrivalMicros,
    );
    _playbackQueue = _playbackQueue
        .then((_) async {
          final decodeClock = Stopwatch()..start();
          final pcm = await decoder.decode(packet.payload);
          _metrics.decoded(decodeClock.elapsed);
          await playbackService.writePcm(pcm);
        })
        .catchError((_) {
          _emitError('Audio playback failed on the receiver.');
          _setStatus(AudioStreamStatus.error);
        });
  }

  @override
  Future<void> stopReceiver() async {
    _receiving = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _jitter.reset();
    _clockSynchronized = false;
    _receiverClock.stop();
    _sessionKey = null;
    _securitySessionId = null;
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
