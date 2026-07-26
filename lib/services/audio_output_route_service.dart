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
    final outputs = (value ?? const <Object?>[]).whereType<Map>().map((raw) {
      return AudioOutputDevice.fromMap(Map<Object?, Object?>.from(raw));
    });
    final unique = <String, AudioOutputDevice>{};
    for (final output in outputs) {
      // Android exposes separate audio profiles and macOS can expose
      // duplicate stream endpoints with the same display name. They are one
      // user-facing output, so keep one row per name/type pair.
      final key = '${output.kind}:${output.name.trim().toLowerCase()}';
      final previous = unique[key];
      if (previous == null || (!previous.isSelected && output.isSelected)) {
        unique[key] = output;
      }
    }
    final sorted = unique.values.toList(growable: false)
      ..sort((a, b) {
        final selectedOrder = (b.isSelected ? 1 : 0).compareTo(
          a.isSelected ? 1 : 0,
        );
        if (selectedOrder != 0) return selectedOrder;
        final kindOrder = a.kind.compareTo(b.kind);
        if (kindOrder != 0) return kindOrder;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return sorted;
  }

  Future<void> selectOutput(String id) async {
    await _channel.invokeMethod<void>('selectOutput', id);
  }

  /// Restores the selected media route after microphone capture. Some Android
  /// devices switch to a communication/Bluetooth-SCO route while recording.
  Future<void> reapplySelectedOutput() async {
    try {
      await _channel.invokeMethod<void>('reapplyOutput');
    } on MissingPluginException {
      // Only Android needs this recovery; other platforms follow system route.
    }
  }
}
