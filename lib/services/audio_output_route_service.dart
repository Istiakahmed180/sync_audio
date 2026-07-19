import 'package:flutter/services.dart';

class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.name,
    required this.kind,
    required this.isBluetooth,
    required this.isSelected,
  });

  final String id;
  final String name;
  final String kind;
  final bool isBluetooth;
  final bool isSelected;

  factory AudioOutputDevice.fromMap(Map<Object?, Object?> map) {
    return AudioOutputDevice(
      id: '${map['id'] ?? ''}',
      name: '${map['name'] ?? 'Audio output'}',
      kind: '${map['kind'] ?? 'unknown'}',
      isBluetooth: map['isBluetooth'] == true,
      isSelected: map['isSelected'] == true,
    );
  }
}

/// Opens the platform audio-output settings page. The native playback engine
/// follows the output selected there, including Bluetooth speakers/headsets.
class AudioOutputRouteService {
  static const _channel = MethodChannel('sync_audio/audio_output');

  Future<void> openSystemOutputSettings() async {
    await _channel.invokeMethod<void>('openOutputSettings');
  }

  Future<List<AudioOutputDevice>> listOutputs() async {
    final value = await _channel.invokeMethod<List<Object?>>('listOutputs');
    return (value ?? const <Object?>[])
        .whereType<Map>()
        .map((raw) {
          return AudioOutputDevice.fromMap(Map<Object?, Object?>.from(raw));
        })
        .toList(growable: false);
  }

  Future<void> selectOutput(String id) async {
    await _channel.invokeMethod<void>('selectOutput', id);
  }
}
