import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';

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
    required String pairingCode,
  });

  Future<void> stopResponder();
}

class UdpDeviceDiscoveryService implements DeviceDiscoveryService {
  UdpDeviceDiscoveryService({IpAddressService? ipAddressService})
    : _ipAddressService = ipAddressService ?? IpAddressService();

  static const discoveryPort = 5054;
  static const _request = 'SYNC_AUDIO_DISCOVER';
  static const _response = 'SYNC_AUDIO_DEVICE';
  static const _mdnsServiceType = '_sync-audio._tcp.local.';
  static const _mdnsAddress = '224.0.0.251';
  static const _mdnsPort = 5353;
  static const _mdnsTtlSeconds = 120;
  final IpAddressService _ipAddressService;
  RawDatagramSocket? _responder;
  StreamSubscription<RawSocketEvent>? _responderSubscription;
  RawDatagramSocket? _mdnsResponder;
  StreamSubscription<RawSocketEvent>? _mdnsResponderSubscription;
  String? _deviceId;
  String? _deviceName;
  int? _controlPort;
  String? _responderAddress;

  @override
  Future<List<AudioDevice>> discover({
    Duration timeout = const Duration(milliseconds: 1800),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;
    final devices = <String, AudioDevice>{};
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final startedAt = DateTime.now();
    final completer = Completer<void>();
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final fields = utf8.decode(datagram!.data).trim().split('|');
        if ((fields.length != 6 && fields.length != 7) ||
            fields.first != _response ||
            fields.last != nonce) {
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
          pairingCode: fields.length == 7 ? fields[5] : null,
          latencyMs: DateTime.now().difference(startedAt).inMilliseconds,
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
    if (devices.isEmpty) {
      // Some access points deliberately drop LAN broadcast packets. mDNS
      // uses multicast and is commonly still permitted in that configuration.
      await _discoverWithMdns(timeout: timeout, devices: devices);
    }
    return devices.values.toList(growable: false);
  }

  Future<void> _discoverWithMdns({
    required Duration timeout,
    required Map<String, AudioDevice> devices,
  }) async {
    final client = MDnsClient();
    try {
      await client.start();
      final pointers = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_mdnsServiceType),
            timeout: timeout,
          )
          .take(32)
          .toList();
      final startedAt = DateTime.now();
      for (final pointer in pointers) {
        final instance = pointer.domainName;
        final services = await client
            .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(instance),
              timeout: timeout,
            )
            .take(1)
            .toList();
        if (services.isEmpty) continue;
        final service = services.first;
        final addresses = await client
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(service.target),
              timeout: timeout,
            )
            .take(1)
            .toList();
        if (addresses.isEmpty) continue;
        final textRecords = await client
            .lookup<TxtResourceRecord>(
              ResourceRecordQuery.text(instance),
              timeout: timeout,
            )
            .take(1)
            .toList();
        final metadata = _parseTxt(textRecords.firstOrNull?.text);
        final address = addresses.first.address.address;
        final id = metadata['id'] ?? instance;
        devices[id] = AudioDevice(
          id: id,
          name: metadata['name'] ?? _displayNameFromInstance(instance),
          ipAddress: address,
          port: service.port,
          pairingCode: metadata['pairing'],
          latencyMs: DateTime.now().difference(startedAt).inMilliseconds,
        );
      }
    } catch (_) {
      // mDNS is best-effort. QR/manual setup must continue to work when the
      // platform or network does not support multicast DNS.
    } finally {
      client.stop();
    }
  }

  Map<String, String> _parseTxt(String? text) {
    if (text == null || text.trim().isEmpty) return const {};
    final result = <String, String>{};
    for (final line in text.split('\n')) {
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      result[line.substring(0, separator)] = line.substring(separator + 1);
    }
    return result;
  }

  String _displayNameFromInstance(String instance) {
    final value = instance.endsWith('.')
        ? instance.substring(0, instance.length - 1)
        : instance;
    final marker = value.indexOf('._sync-audio._tcp');
    return marker > 0 ? value.substring(0, marker) : value;
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
    required String pairingCode,
  }) async {
    await stopResponder();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    // Resolve the Receiver address before starting the responder. The
    // datagram's address below is the request sender (the Host), not the
    // local Receiver address.
    _responderAddress = await _ipAddressService.findPrivateIpv4Address();
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
          _responderAddress ?? datagram.address.address,
          '$_controlPort',
          pairingCode,
          request[1],
        ].join('|');
        socket.send(utf8.encode(response), datagram.address, datagram.port);
      }
    });
    await _startMdnsResponder(pairingCode);
  }

  Future<void> _startMdnsResponder(String pairingCode) async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _mdnsPort,
        reuseAddress: true,
        reusePort: true,
      );
      final multicastAddress = InternetAddress(_mdnsAddress);
      for (final network in await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      )) {
        socket.joinMulticast(multicastAddress, network);
      }
      _mdnsResponder = socket;
      _mdnsResponderSubscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket.receive()) != null) {
          if (!_isMdnsServiceQuery(datagram!.data)) continue;
          final response = _buildMdnsResponse(pairingCode);
          socket.send(response, multicastAddress, _mdnsPort);
        }
      });
    } catch (_) {
      // A platform may deny multicast DNS while still allowing the legacy
      // broadcast responder. Do not prevent the Receiver from starting.
      await _stopMdnsResponder();
    }
  }

  bool _isMdnsServiceQuery(List<int> bytes) {
    if (bytes.length < 13) return false;
    final data = ByteData.sublistView(Uint8List.fromList(bytes));
    final questionCount = data.getUint16(4);
    var offset = 12;
    for (var question = 0; question < questionCount; question++) {
      final name = _readMdnsName(bytes, offset);
      if (name == null) return false;
      offset = name.nextOffset + 4;
      if (offset > bytes.length) return false;
      if (name.value.toLowerCase() == _mdnsServiceType) return true;
    }
    return false;
  }

  _MdnsName? _readMdnsName(List<int> bytes, int offset) {
    final labels = <String>[];
    while (offset < bytes.length) {
      final length = bytes[offset++];
      if (length == 0) {
        return _MdnsName('${labels.join('.')}.', offset);
      }
      if (length > 63 || offset + length > bytes.length) return null;
      labels.add(utf8.decode(bytes.sublist(offset, offset + length)));
      offset += length;
    }
    return null;
  }

  Uint8List _buildMdnsResponse(String pairingCode) {
    final deviceId = _deviceId ?? 'receiver';
    final address = InternetAddress.tryParse(_responderAddress ?? '');
    if (address == null || address.type != InternetAddressType.IPv4) {
      return Uint8List(0);
    }
    final instance =
        '${_sanitizeMdnsLabel(_deviceName ?? 'Receiver')}-$deviceId.$_mdnsServiceType';
    final target = 'sync-audio-$deviceId.local.';
    final records = <int>[];
    _writeMdnsHeader(records, answerCount: 4);
    _writeMdnsRecord(
      records,
      name: _mdnsServiceType,
      type: 12,
      rdata: _encodeMdnsName(instance),
      unique: false,
    );
    final srvData = <int>[
      0,
      0,
      0,
      0,
      ..._uint16(_controlPort ?? 5050),
      ..._encodeMdnsName(target),
    ];
    _writeMdnsRecord(
      records,
      name: instance,
      type: 33,
      rdata: srvData,
      unique: true,
    );
    final txt = <int>[];
    for (final value in [
      'id=$deviceId',
      'name=${_deviceName ?? 'Receiver'}',
      'pairing=$pairingCode',
    ]) {
      final encoded = utf8.encode(value);
      if (encoded.length <= 255) txt.add(encoded.length);
      txt.addAll(encoded.take(255));
    }
    _writeMdnsRecord(
      records,
      name: instance,
      type: 16,
      rdata: txt,
      unique: true,
    );
    _writeMdnsRecord(
      records,
      name: target,
      type: 1,
      rdata: address.rawAddress,
      unique: true,
    );
    return Uint8List.fromList(records);
  }

  void _writeMdnsHeader(List<int> output, {required int answerCount}) {
    output.addAll([0, 0, 0x84, 0, 0, 0, ..._uint16(answerCount), 0, 0, 0, 0]);
  }

  void _writeMdnsRecord(
    List<int> output, {
    required String name,
    required int type,
    required List<int> rdata,
    required bool unique,
  }) {
    output.addAll(_encodeMdnsName(name));
    output.addAll(_uint16(type));
    output.addAll(_uint16(unique ? 0x8001 : 1));
    output.addAll([0, 0, 0, _mdnsTtlSeconds]);
    output.addAll(_uint16(rdata.length));
    output.addAll(rdata);
  }

  List<int> _encodeMdnsName(String value) {
    final normalized = value.endsWith('.')
        ? value.substring(0, value.length - 1)
        : value;
    final output = <int>[];
    for (final label in normalized.split('.')) {
      final encoded = utf8.encode(label);
      output.add(encoded.length);
      output.addAll(encoded);
    }
    output.add(0);
    return output;
  }

  List<int> _uint16(int value) => [(value >> 8) & 0xff, value & 0xff];

  String _sanitizeMdnsLabel(String value) {
    final sanitized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '-');
    return sanitized.isEmpty
        ? 'Receiver'
        : sanitized.substring(0, sanitized.length.clamp(1, 50));
  }

  @override
  Future<void> stopResponder() async {
    await _responderSubscription?.cancel();
    _responderSubscription = null;
    _responder?.close();
    _responder = null;
    _responderAddress = null;
    await _stopMdnsResponder();
  }

  Future<void> _stopMdnsResponder() async {
    await _mdnsResponderSubscription?.cancel();
    _mdnsResponderSubscription = null;
    _mdnsResponder?.close();
    _mdnsResponder = null;
  }
}

class _MdnsName {
  const _MdnsName(this.value, this.nextOffset);

  final String value;
  final int nextOffset;
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
    required String pairingCode,
  }) async {}

  @override
  Future<void> stopResponder() async {}
}
