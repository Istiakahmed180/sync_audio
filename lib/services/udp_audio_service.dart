import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';

import '../models/audio_stream_status.dart';
import '../models/receiver_session.dart';
import 'audio_capture_service.dart';
import 'audio_packet_codec.dart';
import 'audio_playback_service.dart';

abstract class AudioStreamService {
  Stream<AudioStreamStatus> get statusChanges;
  Stream<String> get errors;
  Stream<ReceiverSession> get sessionChanges;
  AudioStreamStatus get status;
  bool get isStreaming;
  bool get isReceiving;
  List<ReceiverSession> get receiverSessions;

  Future<void> startStreaming({
    required List<String> ipAddresses,
    required int port,
  });
  Future<void> stopStreaming();
  Future<void> startReceiver({required int port});
  Future<void> stopReceiver();
}

class UdpAudioService implements AudioStreamService {
  UdpAudioService({
    required this.playbackService,
    required this.captureService,
    this.jitterBuffer = const Duration(milliseconds: 120),
    this.syncInterval = const Duration(seconds: 2),
  });

  static const futurePlaybackDelay = Duration(milliseconds: 120);

  final AudioPlaybackService playbackService;
  final AudioCaptureService captureService;
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
      _streamClock = Stopwatch()..start();
      _sessions
        ..clear()
        ..addEntries(
          _destinations.map((address) {
            final id = _sessionId(address.address, port);
            final session = ReceiverSession(
              id: id,
              ipAddress: address.address,
              port: port,
              status: ReceiverSessionStatus.synchronizing,
            );
            _emitSession(session);
            return MapEntry(id, session);
          }),
        );
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
      final offset =
          ((packet.timestampMicros - request.sentAtMicros) +
              (packet.timestampMicros - receivedAt)) ~/
          2;
      final session = _sessions[request.sessionId];
      if (session == null) continue;
      final updated = session.copyWith(
        status: ReceiverSessionStatus.connected,
        clockOffsetMicros: offset,
        roundTripTimeMicros: receivedAt - request.sentAtMicros,
        lastSyncMicros: receivedAt,
        reconnectAttempt: 0,
      );
      _updateSession(updated);
      final address = InternetAddress(updated.ipAddress);
      _socket!.send(
        AudioPacketCodec.encode(
          type: AudioPacketType.clockOffset,
          sequence: packet.sequence,
          timestampMicros: offset,
        ),
        address,
        updated.port,
      );
    }
  }

  Future<void> _handleCaptureError() async {
    await stopStreaming();
    _emitError('System audio capture failed.');
    _setStatus(AudioStreamStatus.error);
  }

  void _sendPcmPacket(Uint8List pcm) {
    final socket = _socket;
    final clock = _streamClock;
    if (!_streaming || socket == null || clock == null || pcm.isEmpty) return;
    final packet = AudioPacketCodec.encode(
      type: AudioPacketType.pcmAudio,
      sequence: _packetSequence++,
      timestampMicros:
          clock.elapsedMicroseconds + futurePlaybackDelay.inMicroseconds,
      payload: pcm,
    );
    for (final destination in _destinations) {
      socket.send(packet, destination, _destinationPort);
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
    _streamClock?.stop();
    _streamClock = null;
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
      final packet = AudioPacketCodec.decode(source.data);
      if (packet == null) continue;
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
          _nextSequence ??= packet.sequence;
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
        _nextSequence = _pendingPackets.keys.reduce((a, b) => a < b ? a : b);
      }
      return;
    }
    if (_receiverClock.elapsedMicroseconds <
        packet.timestampMicros + _hostToLocalOffsetMicros) {
      return;
    }
    _pendingPackets.remove(sequence);
    _nextSequence = (sequence + 1) & 0xFFFFFFFF;
    _playbackQueue = _playbackQueue
        .then((_) => playbackService.writePcm(packet.pcm))
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
