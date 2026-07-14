import 'dart:typed_data';

import 'package:opus_codec/opus_codec.dart' as opus_loader;
import 'package:opus_codec_dart/opus_codec_dart.dart';
import 'package:opus_codec_dart/wrappers/opus_defines.dart';

enum AudioCodecType { pcm16, opus }

enum AudioCodecPreference { pcm, opus, auto }

class AudioCodecConfig {
  const AudioCodecConfig({
    this.sampleRate = 48000,
    this.channels = 1,
    this.bitrate = 64000,
    this.frameDurationMs = 20,
  });

  final int sampleRate;
  final int channels;
  final int bitrate;
  final int frameDurationMs;

  int get frameBytes => sampleRate * channels * 2 * frameDurationMs ~/ 1000;
}

class OpusRuntime {
  static bool isAvailable = false;

  static Future<void> initialize() async {
    try {
      initOpus(await opus_loader.load());
      isAvailable = true;
    } catch (_) {
      isAvailable = false;
    }
  }
}

abstract class AudioEncoder {
  AudioCodecType get codecType;
  AudioCodecConfig get config;
  Future<Uint8List> encode(Uint8List pcm);
  Future<void> reset();
}

abstract class AudioDecoder {
  AudioCodecType get codecType;
  AudioCodecConfig get config;
  Future<Uint8List> decode(Uint8List encoded);
  Future<void> reset();
}

class Pcm16AudioEncoder implements AudioEncoder {
  Pcm16AudioEncoder({this.config = const AudioCodecConfig()});

  @override
  final AudioCodecConfig config;

  @override
  AudioCodecType get codecType => AudioCodecType.pcm16;

  @override
  Future<Uint8List> encode(Uint8List pcm) async => pcm;

  @override
  Future<void> reset() async {}
}

class Pcm16AudioDecoder implements AudioDecoder {
  Pcm16AudioDecoder({this.config = const AudioCodecConfig()});

  @override
  final AudioCodecConfig config;

  @override
  AudioCodecType get codecType => AudioCodecType.pcm16;

  @override
  Future<Uint8List> decode(Uint8List encoded) async => encoded;

  @override
  Future<void> reset() async {}
}

class UnsupportedOpusEncoder implements AudioEncoder {
  UnsupportedOpusEncoder({this.config = const AudioCodecConfig()});

  @override
  final AudioCodecConfig config;

  @override
  AudioCodecType get codecType => AudioCodecType.opus;

  @override
  Future<Uint8List> encode(Uint8List pcm) => Future<Uint8List>.error(
    UnsupportedError(
      'Opus encoding requires a native Opus backend; PCM remains enabled.',
    ),
  );

  @override
  Future<void> reset() async {}
}

class UnsupportedOpusDecoder implements AudioDecoder {
  UnsupportedOpusDecoder({this.config = const AudioCodecConfig()});

  @override
  final AudioCodecConfig config;

  @override
  AudioCodecType get codecType => AudioCodecType.opus;

  @override
  Future<Uint8List> decode(Uint8List encoded) => Future<Uint8List>.error(
    UnsupportedError(
      'Opus decoding requires a native Opus backend; PCM remains enabled.',
    ),
  );

  @override
  Future<void> reset() async {}
}

class NativeOpusAudioEncoder implements AudioEncoder {
  NativeOpusAudioEncoder({this.config = const AudioCodecConfig()}) {
    _create();
  }

  @override
  final AudioCodecConfig config;
  BufferedOpusEncoder? _encoder;

  @override
  AudioCodecType get codecType => AudioCodecType.opus;

  void _create() {
    if (!OpusRuntime.isAvailable) {
      throw StateError('Native Opus is unavailable on this device.');
    }
    final encoder = BufferedOpusEncoder(
      sampleRate: config.sampleRate,
      channels: config.channels,
      application: Application.audio,
      maxInputBufferSizeBytes: config.frameBytes,
    );
    encoder.encoderCtl(
      request: OPUS_SET_BITRATE_REQUEST,
      value: config.bitrate,
    );
    _encoder = encoder;
  }

  @override
  Future<Uint8List> encode(Uint8List pcm) async {
    if (pcm.length != config.frameBytes) {
      throw ArgumentError.value(
        pcm.length,
        'pcm.length',
        'Opus frames must be exactly ${config.frameBytes} bytes.',
      );
    }
    final encoder = _encoder;
    if (encoder == null) {
      throw StateError('Opus encoder is not initialized.');
    }
    encoder.inputBuffer.setAll(0, pcm);
    encoder.inputBufferIndex = pcm.length;
    return encoder.encode();
  }

  @override
  Future<void> reset() async {
    _encoder?.destroy();
    _create();
  }
}

class NativeOpusAudioDecoder implements AudioDecoder {
  NativeOpusAudioDecoder({this.config = const AudioCodecConfig()}) {
    _create();
  }

  @override
  final AudioCodecConfig config;
  SimpleOpusDecoder? _decoder;

  @override
  AudioCodecType get codecType => AudioCodecType.opus;

  void _create() {
    if (!OpusRuntime.isAvailable) {
      throw StateError('Native Opus is unavailable on this device.');
    }
    _decoder = SimpleOpusDecoder(
      sampleRate: config.sampleRate,
      channels: config.channels,
    );
  }

  @override
  Future<Uint8List> decode(Uint8List encoded) async {
    final decoder = _decoder;
    if (decoder == null) {
      throw StateError('Opus decoder is not initialized.');
    }
    final pcm = decoder.decode(input: encoded);
    return Uint8List.fromList(
      pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes),
    );
  }

  @override
  Future<void> reset() async {
    _decoder?.destroy();
    _create();
  }
}
