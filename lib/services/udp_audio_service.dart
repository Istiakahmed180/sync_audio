import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/audio_stream_status.dart';
import 'audio_capture_service.dart';
import 'audio_playback_service.dart';

abstract class AudioStreamService {
  Stream<AudioStreamStatus> get statusChanges;
  Stream<String> get errors;
  AudioStreamStatus get status;
  bool get isStreaming;
  bool get isReceiving;

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
  });

  static const _packetHeaderBytes = 12;

  final AudioPlaybackService playbackService;
  final AudioCaptureService captureService;
  final Duration jitterBuffer;
  final _statusController = StreamController<AudioStreamStatus>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  StreamSubscription<Uint8List>? _captureSubscription;
  Timer? _playbackTimer;
  Future<void> _playbackQueue = Future<void>.value();
  AudioStreamStatus _status = AudioStreamStatus.idle;
  bool _streaming = false;
  bool _receiving = false;
  List<InternetAddress> _destinations = const [];
  int _destinationPort = 0;
  int _packetSequence = 0;
  Stopwatch? _streamClock;
  final Stopwatch _receiverClock = Stopwatch();
  final Map<int, _ReceivedAudioPacket> _pendingPackets =
      <int, _ReceivedAudioPacket>{};
  int? _nextSequence;
  int? _firstPacketTimestamp;
  int? _playbackStartMicros;

  @override
  Stream<AudioStreamStatus> get statusChanges => _statusController.stream;

  @override
  Stream<String> get errors => _errorsController.stream;

  @override
  AudioStreamStatus get status => _status;

  @override
  bool get isStreaming => _streaming;

  @override
  bool get isReceiving => _receiving;

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
      _streamClock = Stopwatch()..start();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _captureSubscription = captureService.pcmChunks.listen(
        _sendPcmPacket,
        onError: (_) => unawaited(_handleCaptureError()),
      );
      _streaming = true;
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

  Future<void> _handleCaptureError() async {
    await stopStreaming();
    _emitError('System audio capture failed.');
    _setStatus(AudioStreamStatus.error);
  }

  void _sendPcmPacket(Uint8List pcm) {
    final socket = _socket;
    final clock = _streamClock;
    if (!_streaming || socket == null || clock == null || pcm.isEmpty) return;

    final packet = Uint8List(_packetHeaderBytes + pcm.length);
    final data = ByteData.sublistView(packet);
    data.setUint32(0, _packetSequence++, Endian.big);
    data.setUint64(4, clock.elapsedMicroseconds, Endian.big);
    packet.setRange(_packetHeaderBytes, packet.length, pcm);
    for (final destination in _destinations) {
      socket.send(packet, destination, _destinationPort);
    }
  }

  @override
  Future<void> stopStreaming() async {
    await _captureSubscription?.cancel();
    _captureSubscription = null;
    await captureService.stop();
    _streaming = false;
    _streamClock?.stop();
    _streamClock = null;
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
      _receiverClock
        ..reset()
        ..start();
      _playbackTimer = Timer.periodic(
        const Duration(milliseconds: 5),
        (_) => _drainPlaybackBuffer(),
      );
      _setStatus(AudioStreamStatus.receiving);
      _socketSubscription = _socket!.listen(_handleSocketEvent);
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

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || !_receiving) return;
    Datagram? datagram;
    while ((datagram = _socket?.receive()) != null) {
      final data = datagram!.data;
      if (data.length <= _packetHeaderBytes) continue;
      final header = ByteData.sublistView(data);
      final sequence = header.getUint32(0, Endian.big);
      final timestamp = header.getUint64(4, Endian.big);
      _nextSequence ??= sequence;
      _firstPacketTimestamp ??= timestamp;
      _playbackStartMicros ??=
          _receiverClock.elapsedMicroseconds + jitterBuffer.inMicroseconds;
      _pendingPackets.putIfAbsent(
        sequence,
        () => _ReceivedAudioPacket(
          sequence: sequence,
          timestampMicros: timestamp,
          pcm: Uint8List.fromList(data.sublist(_packetHeaderBytes)),
        ),
      );
    }
  }

  void _drainPlaybackBuffer() {
    final nextSequence = _nextSequence;
    final firstTimestamp = _firstPacketTimestamp;
    final playbackStart = _playbackStartMicros;
    if (!_receiving ||
        nextSequence == null ||
        firstTimestamp == null ||
        playbackStart == null) {
      return;
    }

    final packet = _pendingPackets[nextSequence];
    if (packet == null) {
      if (_pendingPackets.isNotEmpty &&
          _receiverClock.elapsedMicroseconds > playbackStart + 30000) {
        _nextSequence = _pendingPackets.keys.reduce((a, b) => a < b ? a : b);
      }
      return;
    }

    final dueMicros = playbackStart + (packet.timestampMicros - firstTimestamp);
    if (_receiverClock.elapsedMicroseconds < dueMicros) return;
    _pendingPackets.remove(nextSequence);
    _nextSequence = (nextSequence + 1) & 0xFFFFFFFF;
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
    _firstPacketTimestamp = null;
    _playbackStartMicros = null;
    _receiverClock.stop();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    if (!_streaming) {
      _socket?.close();
      _socket = null;
    }
    await playbackService.stop();
    _setStatus(AudioStreamStatus.stopped);
  }

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
  }
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
