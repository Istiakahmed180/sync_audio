import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../models/audio_stream_status.dart';
import 'audio_playback_service.dart';
import 'audio_tone_generator.dart';

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
  UdpAudioService({required this.playbackService});

  final AudioPlaybackService playbackService;
  final _statusController = StreamController<AudioStreamStatus>.broadcast();
  final _errorsController = StreamController<String>.broadcast();
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _socketSubscription;
  Timer? _toneTimer;
  Future<void> _playbackQueue = Future<void>.value();
  AudioStreamStatus _status = AudioStreamStatus.idle;
  bool _streaming = false;
  bool _receiving = false;
  InternetAddress? _destination;
  int _destinationPort = 0;
  AudioToneGenerator? _toneGenerator;

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
      _emitError('The test tone is already streaming.');
      return;
    }
    _setStatus(AudioStreamStatus.starting);
    try {
      _destination = InternetAddress(ipAddress);
      _destinationPort = port;
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _toneGenerator = AudioToneGenerator();
      _streaming = true;
      _setStatus(AudioStreamStatus.streaming);
      final interval = Duration(
        microseconds:
            (AudioToneGenerator().framesPerPacket /
                    AudioToneGenerator().sampleRate *
                    1000000)
                .round(),
      );
      _toneTimer = Timer.periodic(interval, (_) => _sendTonePacket());
      _sendTonePacket();
    } on SocketException {
      await stopStreaming();
      _emitError('Unable to start UDP audio. Check the network connection.');
      _setStatus(AudioStreamStatus.error);
    }
  }

  void _sendTonePacket() {
    final socket = _socket;
    final destination = _destination;
    final generator = _toneGenerator;
    if (!_streaming ||
        socket == null ||
        destination == null ||
        generator == null) {
      return;
    }
    socket.send(generator.nextPacket(), destination, _destinationPort);
  }

  @override
  Future<void> stopStreaming() async {
    _toneTimer?.cancel();
    _toneTimer = null;
    _streaming = false;
    if (!_receiving) _socket?.close();
    if (!_receiving) _socket = null;
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
    if (!_streaming) _socket?.close();
    if (!_streaming) _socket = null;
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
