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

  Future<void> startStreaming({required String ipAddress, required int port});
  Future<void> stopStreaming();
  Future<void> startReceiver({required int port});
  Future<void> stopReceiver();
}

class UdpAudioService implements AudioStreamService {
  UdpAudioService({
    required this.playbackService,
    required this.captureService,
  });

  final AudioPlaybackService playbackService;
  final AudioCaptureService captureService;
  final _statusController = StreamController<AudioStreamStatus>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  StreamSubscription<Uint8List>? _captureSubscription;
  Future<void> _playbackQueue = Future<void>.value();
  AudioStreamStatus _status = AudioStreamStatus.idle;
  bool _streaming = false;
  bool _receiving = false;
  InternetAddress? _destination;
  int _destinationPort = 0;
  int _packetSequence = 0;

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
    required String ipAddress,
    required int port,
  }) async {
    if (_streaming) {
      _emitError('Microphone streaming is already running.');
      return;
    }
    _setStatus(AudioStreamStatus.starting);
    try {
      _destination = InternetAddress(ipAddress);
      _destinationPort = port;
      _packetSequence = 0;
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _captureSubscription = captureService.pcmChunks.listen(
        _sendPcmPacket,
        onError: (_) {
          _emitError('Microphone audio capture failed.');
          _setStatus(AudioStreamStatus.error);
        },
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
      final message = error.code == 'MICROPHONE_PERMISSION_DENIED'
          ? 'Microphone permission is required to start audio capture.'
          : 'Unable to start microphone capture.';
      _emitError(message);
      _setStatus(AudioStreamStatus.error);
    } catch (_) {
      await stopStreaming();
      _emitError('Unable to start microphone capture.');
      _setStatus(AudioStreamStatus.error);
    }
  }

  void _sendPcmPacket(Uint8List pcm) {
    final socket = _socket;
    final destination = _destination;
    if (!_streaming) return;
    if (socket == null || destination == null || pcm.isEmpty) return;

    final packet = Uint8List(4 + pcm.length);
    final data = ByteData.sublistView(packet);
    data.setUint32(0, _packetSequence++, Endian.big);
    packet.setRange(4, packet.length, pcm);
    socket.send(packet, destination, _destinationPort);
  }

  @override
  Future<void> stopStreaming() async {
    await _captureSubscription?.cancel();
    _captureSubscription = null;
    await captureService.stop();
    _streaming = false;
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
      if (data.length <= 4) continue;
      final pcm = Uint8List.fromList(data.sublist(4));
      _playbackQueue = _playbackQueue
          .then((_) => playbackService.writePcm(pcm))
          .catchError((_) {
            _emitError('Audio playback failed on the receiver.');
            _setStatus(AudioStreamStatus.error);
          });
    }
  }

  @override
  Future<void> stopReceiver() async {
    _receiving = false;
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
