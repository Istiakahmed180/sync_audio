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

  static const futurePlaybackDelay = Duration(milliseconds: 120);

  final AudioPlaybackService playbackService;
  final AudioCaptureService captureService;
  AudioEncoder encoder;
  AudioDecoder decoder;
  final Duration jitterBuffer;
  final Duration syncInterval;
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
  final Map<int, _ReceivedAudioPacket> _pendingPackets =
      <int, _ReceivedAudioPacket>{};
  int? _nextSequence;
  int? _missingSequenceSinceMicros;
  int _droppedPackets = 0;
  SecretKey? _sessionKey;
  String? _securitySessionId;
  final _sessionKeyService = SessionKeyService();
  final _replayGuard = ReplayGuard();
  int _hostToLocalOffsetMicros = 0;
  bool _clockSynchronized = false;

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
  int get bufferedPackets => _pendingPackets.length;

  @override
  int get bufferedDurationMicros {
    if (_pendingPackets.isEmpty) return 0;
    final packets = _pendingPackets.values.toList()
      ..sort((a, b) => a.timestampMicros.compareTo(b.timestampMicros));
    return packets.last.timestampMicros - packets.first.timestampMicros;
  }

  @override
  int get droppedPacketCount => _droppedPackets;

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
    } catch (_) {
      await stopStreaming();
      _emitError('Unable to start system audio capture.');
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
      _sendClockOffset(updated, packet.sequence);
    }
  }

  Future<void> _handleCaptureError() async {
    await stopStreaming();
    _emitError('System audio capture failed.');
    _setStatus(AudioStreamStatus.error);
  }

  void _sendPcmPacket(Uint8List pcm) {
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
    await stopStreaming();
    _emitError(
      'Audio encoding failed. PCM fallback remains available when selected.',
    );
    _setStatus(AudioStreamStatus.error);
  }

  Future<void> _encodeAndSendPcm(Uint8List pcm) async {
    final socket = _socket;
    final clock = _streamClock;
    if (!_streaming || socket == null || clock == null || pcm.isEmpty) return;
    final encoded = await encoder.encode(pcm);
    if (!_streaming || encoded.isEmpty) return;
    final packet = AudioPacketCodec.encode(
      type: AudioPacketType.pcmAudio,
      sequence: _packetSequence++,
      timestampMicros:
          clock.elapsedMicroseconds + futurePlaybackDelay.inMicroseconds,
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
    if (!_receiving) {
      _socket?.close();
      _socket = null;
    }
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

  @override
  Future<void> startReceiver({required int port}) async {
    if (_receiving) {
      _emitError('The audio receiver is already running.');
      return;
    }
    _setStatus(AudioStreamStatus.starting);
    try {
      await playbackService.start();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _receiving = true;
      _clockSynchronized = false;
      _hostToLocalOffsetMicros = 0;
      _receiverClock
        ..reset()
        ..start();
      _playbackTimer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => _drainPlaybackBuffer(),
      );
      _setStatus(AudioStreamStatus.receiving);
      _udpSubscription = _socket!.listen(_handleReceiverSocketEvent);
    } on SocketException {
      await stopReceiver();
      _emitError('Unable to start the UDP audio receiver. Port may be in use.');
      _setStatus(AudioStreamStatus.error);
    } catch (_) {
      await stopReceiver();
      _emitError('Unable to initialize Android audio playback.');
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
    if (EncryptedAudioPacketCodec.isEncrypted(data)) {
      final key = _sessionKey;
      final sessionId = _securitySessionId;
      if (key == null || sessionId == null) return;
      try {
        data = await EncryptedAudioPacketCodec.decrypt(
          packet: data,
          key: key,
          sessionId: sessionId,
          replayGuard: _replayGuard,
        );
      } catch (_) {
        _emitError('Encrypted audio packet rejected.');
        return;
      }
    }
    final packet = AudioPacketCodec.decode(data);
    if (packet == null) return;
    switch (packet.type) {
      case AudioPacketType.clockSyncRequest:
        final now = _receiverClock.elapsedMicroseconds;
        _socket!.send(
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
      case AudioPacketType.pcmAudio:
        if (packet.codecType != decoder.codecType) return;
        _nextSequence ??= packet.sequence;
        if (_pendingPackets.length > 256) {
          final oldest = _pendingPackets.keys.reduce((a, b) => a < b ? a : b);
          _pendingPackets.remove(oldest);
          _droppedPackets++;
        }
        _pendingPackets.putIfAbsent(
          packet.sequence,
          () => _ReceivedAudioPacket(
            sequence: packet.sequence,
            timestampMicros: packet.timestampMicros,
            pcm: packet.payload,
          ),
        );
      case AudioPacketType.clockSyncResponse:
        break;
    }
  }

  void _drainPlaybackBuffer() {
    final sequence = _nextSequence;
    if (!_receiving || !_clockSynchronized || sequence == null) {
      if (_receiving && _clockSynchronized && _pendingPackets.isNotEmpty) {
        _nextSequence = _pendingPackets.keys.reduce((a, b) => a < b ? a : b);
      }
      return;
    }
    final packet = _pendingPackets[sequence];
    if (packet == null) {
      if (_pendingPackets.isNotEmpty) {
        final now = _receiverClock.elapsedMicroseconds;
        _missingSequenceSinceMicros ??= now;
        if (now - _missingSequenceSinceMicros! >=
            const Duration(milliseconds: 40).inMicroseconds) {
          _droppedPackets++;
          _nextSequence = _pendingPackets.keys.reduce((a, b) => a < b ? a : b);
          _missingSequenceSinceMicros = null;
        }
      }
      return;
    }
    if (_receiverClock.elapsedMicroseconds <
        packet.timestampMicros + _hostToLocalOffsetMicros) {
      return;
    }
    _pendingPackets.remove(sequence);
    _nextSequence = (sequence + 1) & 0xFFFFFFFF;
    _missingSequenceSinceMicros = null;
    _playbackQueue = _playbackQueue
        .then((_) async {
          final pcm = await decoder.decode(packet.pcm);
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
    _pendingPackets.clear();
    _nextSequence = null;
    _missingSequenceSinceMicros = null;
    _clockSynchronized = false;
    _receiverClock.stop();
    await _udpSubscription?.cancel();
    _udpSubscription = null;
    if (!_streaming) {
      _socket?.close();
      _socket = null;
    }
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

  String _sessionId(String ipAddress, int port) => ipAddress;

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

class _ReceivedAudioPacket {
  const _ReceivedAudioPacket({
    required this.sequence,
    required this.timestampMicros,
    required this.pcm,
  });

  final int sequence;
  final int timestampMicros;
  final Uint8List pcm;
}
