import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/audio_device.dart';
import 'ip_address_service.dart';

abstract class DeviceDiscoveryService {
  Future<List<AudioDevice>> discover({
    Duration timeout = const Duration(milliseconds: 900),
  });

  Future<void> startResponder({
    required String deviceId,
    required String deviceName,
    required int controlPort,
  });

  Future<void> stopResponder();
}

class UdpDeviceDiscoveryService implements DeviceDiscoveryService {
  UdpDeviceDiscoveryService({IpAddressService? ipAddressService})
    : _ipAddressService = ipAddressService ?? IpAddressService();

  static const discoveryPort = 5054;
  static const _request = 'SYNC_AUDIO_DISCOVER';
  static const _response = 'SYNC_AUDIO_DEVICE';
  final IpAddressService _ipAddressService;
  RawDatagramSocket? _responder;
  StreamSubscription<RawSocketEvent>? _responderSubscription;
  String? _deviceId;
  String? _deviceName;
  int? _controlPort;

  @override
  Future<List<AudioDevice>> discover({
    Duration timeout = const Duration(milliseconds: 1800),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final devices = <String, AudioDevice>{};
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final completer = Completer<void>();
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final fields = utf8.decode(datagram!.data).trim().split('|');
        if (fields.length != 6 ||
            fields.first != _response ||
            fields[5] != nonce) {
          continue;
        }
        final port = int.tryParse(fields[4]);
        if (port == null || port < 1 || port > 65535) continue;
        final address = fields[3].isEmpty
            ? datagram.address.address
            : fields[3];
        devices[fields[1]] = AudioDevice(
          id: fields[1],
          name: fields[2],
          ipAddress: address,
          port: port,
        );
      }
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete();
    });
    try {
      final payload = utf8.encode('$_request|$nonce');
      final targets = <String>{'255.255.255.255'};
      for (final network in await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      )) {
        for (final interfaceAddress in network.addresses) {
          final broadcast = _directedBroadcast(interfaceAddress);
          if (broadcast != null) targets.add(broadcast);
        }
      }
      // Some access points drop the limited broadcast but allow a subnet
      // directed broadcast. Send a few times because Wi-Fi can drop UDP.
      for (var attempt = 0; attempt < 3; attempt++) {
        for (final target in targets) {
          socket.send(payload, InternetAddress(target), discoveryPort);
        }
        if (attempt < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
      }
    } catch (_) {
      completer.complete();
    }
    await completer.future;
    timer.cancel();
    try {
      await subscription.cancel();
      socket.close();
    } catch (_) {
      socket.close();
    }
    return devices.values.toList(growable: false);
  }

  String? _directedBroadcast(InternetAddress address) {
    final rawAddress = address.rawAddress;
    if (rawAddress.length != 4) return null;
    // Most home/mobile Wi-Fi networks are /24. Keep the limited broadcast
    // too, since it covers networks with a different subnet mask.
    final bytes = [...rawAddress.sublist(0, 3), 255];
    return bytes.join('.');
  }

  @override
  Future<void> startResponder({
    required String deviceId,
    required String deviceName,
    required int controlPort,
  }) async {
    await stopResponder();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    // Resolve the preferred address before starting the responder so custom
    // address providers retain their validation behavior. The actual reply
    // address is taken from the receiving interface below.
    await _ipAddressService.findPrivateIpv4Address();
    _deviceId = deviceId;
    _deviceName = deviceName;
    _controlPort = controlPort;
    _responder = socket;
    _responderSubscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final request = utf8.decode(datagram!.data).trim().split('|');
        if (request.length != 2 || request.first != _request) continue;
        final response = [
          _response,
          _deviceId,
          _deviceName,
          // Use the address of the interface that received the request. This
          // matters on phones with Wi-Fi, VPN, and mobile interfaces enabled.
          datagram.address.address,
          '$_controlPort',
          request[1],
        ].join('|');
        socket.send(utf8.encode(response), datagram.address, datagram.port);
      }
    });
  }

  @override
  Future<void> stopResponder() async {
    await _responderSubscription?.cancel();
    _responderSubscription = null;
    _responder?.close();
    _responder = null;
  }
}

class PlaceholderDeviceDiscoveryService implements DeviceDiscoveryService {
  @override
  Future<List<AudioDevice>> discover({
    Duration timeout = const Duration(milliseconds: 900),
  }) async => const [];

  @override
  Future<void> startResponder({
    required String deviceId,
    required String deviceName,
    required int controlPort,
  }) async {}

  @override
  Future<void> stopResponder() async {}
}
