import 'dart:io';

import 'package:flutter/services.dart';

class NetworkSnapshot {
  const NetworkSnapshot({
    required this.signature,
    required this.display,
    required this.hasActiveInterface,
  });

  final String signature;
  final String display;
  final bool hasActiveInterface;
}

class NetworkInfoService {
  static const _channel = MethodChannel('sync_audio/network_info');

  Future<String?> connectedNetworkName() async {
    try {
      final name = await _channel.invokeMethod<String>('getNetworkName');
      final trimmed = name?.trim();
      if (trimmed == null || trimmed.isEmpty || _isUnknown(trimmed)) {
        return null;
      }
      return trimmed;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<NetworkSnapshot> readSnapshot() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final entries = <String>[];
      for (final interface in interfaces) {
        final addresses = interface.addresses
            .where((address) => address.address.isNotEmpty)
            .map((address) => address.address)
            .toList(growable: false);
        if (addresses.isNotEmpty) {
          entries.add('${interface.name}:${addresses.join(',')}');
        }
      }
      entries.sort();
      final name = await connectedNetworkName();
      final networkText = entries.isEmpty
          ? 'No active local network found'
          : entries.map((entry) => entry.replaceFirst(':', ': ')).join('  •  ');
      return NetworkSnapshot(
        // SSID availability can change temporarily on Android when the app
        // resumes or permissions are refreshed. It must not make the app
        // report a network change while the local interface is unchanged.
        signature: entries.join('|'),
        display: name == null ? networkText : 'Wi‑Fi: "$name"  •  $networkText',
        hasActiveInterface: entries.isNotEmpty,
      );
    } catch (_) {
      return const NetworkSnapshot(
        signature: 'unavailable',
        display: 'Network information unavailable',
        hasActiveInterface: false,
      );
    }
  }

  bool _isUnknown(String value) {
    final normalized = value.toLowerCase();
    return normalized == '<unknown ssid>' ||
        normalized == 'unknown' ||
        normalized == 'not available';
  }
}
