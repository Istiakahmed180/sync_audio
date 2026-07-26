import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:record/record.dart';

abstract interface class MicrophoneMixController {
  bool get microphoneMixEnabled;
  Future<void> setMicrophoneMixEnabled(bool enabled);
}

abstract class AudioCaptureService {
  Stream<Uint8List> get pcmChunks;
  bool get isCapturing;

  Future<void> start();
  Future<void> stop();
}

class AndroidSystemAudioCaptureService implements AudioCaptureService {
  static const _controlChannel = MethodChannel(
    'sync_audio/system_audio_capture',
  );
  static const _streamChannel = EventChannel('sync_audio/system_audio_stream');

  @override
  Stream<Uint8List> get pcmChunks => _streamChannel
      .receiveBroadcastStream()
      .map(_decodeChunk)
      .where((bytes) => bytes.isNotEmpty);

  Uint8List _decodeChunk(dynamic chunk) {
    if (chunk is Uint8List) return chunk;
    if (chunk is List<int>) return Uint8List.fromList(chunk);
    if (chunk is List<dynamic>) {
      try {
        return Uint8List.fromList(List<int>.from(chunk));
      } catch (_) {}
    }
    return Uint8List(0);
  }

  bool _isCapturing = false;

  @override
  bool get isCapturing => _isCapturing;

  @override
  Future<void> start() async {
    if (_isCapturing) return;
    await _controlChannel.invokeMethod<void>('start');
    _isCapturing = true;
  }

  @override
  Future<void> stop() async {
    if (!_isCapturing) return;
    await _controlChannel.invokeMethod<void>('stop');
    _isCapturing = false;
  }
}

class PlaceholderAudioCaptureService implements AudioCaptureService {
  @override
  Stream<Uint8List> get pcmChunks => const Stream<Uint8List>.empty();

  @override
  bool isCapturing = false;

  @override
  Future<void> start() async => isCapturing = true;

  @override
  Future<void> stop() async => isCapturing = false;
}

/// Adds a mono PCM microphone stream to the platform system-audio stream.
/// Native Android capture is bypassed by the Host when this mode is enabled,
/// so both sources pass through the same Dart mixer and packet pipeline.
class MicrophoneMixAudioCaptureService
    implements AudioCaptureService, MicrophoneMixController {
  MicrophoneMixAudioCaptureService(this.primary);

  final AudioCaptureService primary;
  final _mixedController = StreamController<Uint8List>.broadcast();
  final _micQueue = ListQueue<Uint8List>();
  StreamSubscription<Uint8List>? _primarySubscription;
  StreamSubscription<Uint8List>? _micSubscription;
  AudioRecorder? _recorder;
  bool _microphoneMixEnabled = false;

  @override
  Stream<Uint8List> get pcmChunks => _mixedController.stream;

  @override
  bool get isCapturing => primary.isCapturing;

  @override
  bool get microphoneMixEnabled => _microphoneMixEnabled;

  @override
  Future<void> setMicrophoneMixEnabled(bool enabled) async {
    _microphoneMixEnabled = enabled;
    if (!enabled) await _stopMicrophone();
  }

  @override
  Future<void> start() async {
    await primary.start();
    await _primarySubscription?.cancel();
    _primarySubscription = primary.pcmChunks.listen(_emitMixed);
    if (_microphoneMixEnabled) await _startMicrophone();
  }

  Future<void> _startMicrophone() async {
    await _stopMicrophone();
    final recorder = AudioRecorder();
    if (!await recorder.hasPermission()) return;
    try {
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 48000,
          numChannels: 1,
        ),
      );
      _recorder = recorder;
      _micSubscription = stream.listen((chunk) {
        _micQueue.add(Uint8List.fromList(chunk));
        while (_micQueue.length > 8) {
          _micQueue.removeFirst();
        }
      }, onError: (_) {});
    } catch (_) {
      await recorder.dispose();
    }
  }

  void _emitMixed(Uint8List systemPcm) {
    if (!_microphoneMixEnabled || _micQueue.isEmpty) {
      _mixedController.add(systemPcm);
      return;
    }
    final mic = _micQueue.removeFirst();
    final mixed = Uint8List.fromList(systemPcm);
    final systemData = ByteData.sublistView(mixed);
    final micData = ByteData.sublistView(mic);
    for (var offset = 0; offset + 1 < mixed.length; offset += 2) {
      final micOffset = offset % mic.length;
      final systemSample = systemData.getInt16(offset, Endian.little);
      final micSample = mic.length >= micOffset + 2
          ? micData.getInt16(micOffset, Endian.little)
          : 0;
      final value = (systemSample + micSample * 0.7).round().clamp(
        -32768,
        32767,
      );
      systemData.setInt16(offset, value, Endian.little);
    }
    _mixedController.add(mixed);
  }

  Future<void> _stopMicrophone() async {
    await _micSubscription?.cancel();
    _micSubscription = null;
    _micQueue.clear();
    final recorder = _recorder;
    _recorder = null;
    await recorder?.stop();
    await recorder?.dispose();
  }

  @override
  Future<void> stop() async {
    await _primarySubscription?.cancel();
    _primarySubscription = null;
    await _stopMicrophone();
    await primary.stop();
  }
}
