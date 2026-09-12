import 'dart:io';

class NetworkCandidate {
  const NetworkCandidate({required this.address, required this.interfaceName});

  final String address;
  final String interfaceName;
}

class IpAddressService {
  Future<String?> findPrivateIpv4Address() async {
    final candidates = await listPrivateIpv4Addresses();
    if (candidates.isEmpty) return null;
    return candidates.first.address;
  }

  /// Returns every private IPv4 address, best (most likely Wi-Fi) first.
  ///
  /// The old implementation returned the first private address reported by
  /// the OS. On a real Android phone that is often a cellular (rmnet / 10.x)
  /// or VPN address instead of the Wi-Fi address the Host must use, so the
  /// Receiver QR code advertised an unreachable IP and the Host stayed in
  /// "TCP reconnecting" forever.
  Future<List<NetworkCandidate>> listPrivateIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final candidates = <({NetworkCandidate candidate, int score})>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!_isPrivateIpv4(address.address)) continue;
        candidates.add((
          candidate: NetworkCandidate(
            address: address.address,
            interfaceName: interface.name,
          ),
          score: _scoreInterface(interface.name, address.address),
        ));
      }
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return [for (final entry in candidates) entry.candidate];
  }

  int _scoreInterface(String interfaceName, String address) {
    final name = interfaceName.toLowerCase();
    var score = 0;
    // Prefer likely Wi-Fi interfaces.
    if (name.contains('wlan') ||
        name.contains('wi-fi') ||
        name.contains('wifi') ||
        name.contains('wireless') ||
        name.contains('eth') ||
        name.contains('en0') ||
        name.contains('wlp')) {
      score += 100;
    }
    // Deprioritize cellular, VPN, virtual and container interfaces.
    if (name.contains('rmnet') ||
        name.contains('ccmni') ||
        name.contains('cellular') ||
        name.contains('pdp_ip') ||
        name.contains('tun') ||
        name.contains('tap') ||
        name.contains('vpn') ||
        name.contains('docker') ||
        name.contains('veth') ||
        name.contains('br-') ||
        name.contains('vethernet') ||
        name.contains('virtb') ||
        name.contains('wmware') ||
        name.contains('virtual')) {
      score -= 100;
    }
    // Within the same class, prefer common home subnets over carrier-grade
    // 10.x which is frequently cellular CGNAT.
    if (address.startsWith('192.168.')) {
      score += 10;
    } else if (address.startsWith('172.')) {
      score += 5;
    }
    return score;
  }

  bool _isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 ||
        parts.any((part) => part == null || part < 0 || part > 255)) {
      return false;
    }
    final first = parts[0]!;
    final second = parts[1]!;
    return first == 10 ||
        (first == 192 && second == 168) ||
        (first == 172 && second >= 16 && second <= 31);
  }
}
