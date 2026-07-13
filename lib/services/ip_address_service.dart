import 'dart:io';

class IpAddressService {
  Future<String?> findPrivateIpv4Address() async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final address in interfaces.expand(
      (interface) => interface.addresses,
    )) {
      if (_isPrivateIpv4(address.address)) return address.address;
    }
    return null;
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
