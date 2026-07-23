import 'dart:async';
import 'dart:io';

import 'audio_packet_codec.dart';

enum PreflightCheckState { passed, failed, skipped }

class PreflightCheck {
  const PreflightCheck({
    required this.label,
    required this.state,
    required this.detail,
    this.latencyMs,
  });

  final String label;
  final PreflightCheckState state;
  final String detail;
  final int? latencyMs;
}

class NetworkPreflightResult {
  const NetworkPreflightResult({
    required this.address,
    required this.checks,
    required this.finishedAt,
  });

  final String address;
  final List<PreflightCheck> checks;
  final DateTime finishedAt;

  bool get passed => checks
      .where((check) => check.state != PreflightCheckState.skipped)
      .every((check) => check.state == PreflightCheckState.passed);
}

class NetworkPreflightService {
  Future<NetworkPreflightResult> run({
    required String address,
    required int controlPort,
    required int audioPort,
    required bool isControlConnected,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final checks = <PreflightCheck>[];
    final parsed = InternetAddress.tryParse(address);
    if (parsed == null || parsed.type != InternetAddressType.IPv4) {
      return NetworkPreflightResult(
        address: address,
        checks: const [
          PreflightCheck(
            label: 'IP address',
            state: PreflightCheckState.failed,
            detail: 'Enter a valid IPv4 address.',
          ),
        ],
        finishedAt: DateTime.now(),
      );
    }

    final localSubnet = await _isOnLocalSubnet(parsed);
    checks.add(
      PreflightCheck(
        label: 'Local network',
        state: localSubnet == null
            ? PreflightCheckState.skipped
            : localSubnet
            ? PreflightCheckState.passed
            : PreflightCheckState.failed,
        detail: localSubnet == null
            ? 'Could not verify the local subnet.'
            : localSubnet
            ? 'Receiver appears to be on the same local network.'
            : 'Receiver is not on a detected local subnet.',
      ),
    );

    checks.add(await _checkTcp(parsed, controlPort, timeout));
    checks.add(
      PreflightCheck(
        label: 'Pairing',
        state: isControlConnected
            ? PreflightCheckState.passed
            : PreflightCheckState.skipped,
        detail: isControlConnected
            ? 'Pairing is already active.'
            : 'Connect the Receiver to verify its pairing code.',
      ),
    );
    checks.add(await _checkUdp(parsed, audioPort, timeout));

    return NetworkPreflightResult(
      address: address,
      checks: checks,
      finishedAt: DateTime.now(),
    );
  }

  Future<PreflightCheck> _checkTcp(
    InternetAddress address,
    int port,
    Duration timeout,
  ) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(address, port, timeout: timeout);
      final latency = stopwatch.elapsedMilliseconds;
      return PreflightCheck(
        label: 'TCP control port',
        state: PreflightCheckState.passed,
        detail: 'Port $port is reachable.',
        latencyMs: latency,
      );
    } on SocketException catch (error) {
      return PreflightCheck(
        label: 'TCP control port',
        state: PreflightCheckState.failed,
        detail: _socketError(error, port: port),
      );
    } on TimeoutException {
      return PreflightCheck(
        label: 'TCP control port',
        state: PreflightCheckState.failed,
        detail: 'Port $port timed out. Check the Receiver server and firewall.',
      );
    } finally {
      socket?.destroy();
    }
  }

  Future<PreflightCheck> _checkUdp(
    InternetAddress address,
    int port,
    Duration timeout,
  ) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final stopwatch = Stopwatch()..start();
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final sequence = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
      final packet = AudioPacketCodec.encode(
        type: AudioPacketType.clockSyncRequest,
        sequence: sequence,
        timestampMicros: 0,
      );
      final response = Completer<bool>();
      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = socket?.receive()) != null) {
          final decoded = AudioPacketCodec.decode(datagram!.data);
          if (decoded?.type == AudioPacketType.clockSyncResponse &&
              decoded?.sequence == sequence &&
              !response.isCompleted) {
            response.complete(true);
          }
        }
      });
      socket.send(packet, address, port);
      final received = await response.future.timeout(
        timeout,
        onTimeout: () => false,
      );
      if (!received) {
        return PreflightCheck(
          label: 'UDP audio port',
          state: PreflightCheckState.failed,
          detail:
              'No UDP response from port $port. Start the Receiver audio service or check Wi‑Fi isolation/firewall.',
        );
      }
      return PreflightCheck(
        label: 'UDP audio port',
        state: PreflightCheckState.passed,
        detail: 'Audio packets can reach the Receiver.',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } on SocketException catch (error) {
      return PreflightCheck(
        label: 'UDP audio port',
        state: PreflightCheckState.failed,
        detail: _socketError(error, port: port),
      );
    } finally {
      await subscription?.cancel();
      socket?.close();
    }
  }

  Future<bool?> _isOnLocalSubnet(InternetAddress target) async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final targetBytes = target.rawAddress;
      if (targetBytes.length != 4) return null;
      for (final network in interfaces) {
        for (final address in network.addresses) {
          final bytes = address.rawAddress;
          if (bytes.length == 4 &&
              bytes[0] == targetBytes[0] &&
              bytes[1] == targetBytes[1] &&
              bytes[2] == targetBytes[2]) {
            return true;
          }
        }
      }
      return false;
    } catch (_) {
      return null;
    }
  }

  String _socketError(SocketException error, {required int port}) {
    final message = error.message.toLowerCase();
    if (message.contains('refused')) {
      return 'Port $port refused the connection. Is the Receiver service running?';
    }
    if (message.contains('unreachable')) {
      return 'Receiver is unreachable. Check the IP and Wi‑Fi network.';
    }
    return 'Could not reach port $port. Check the IP, firewall, and Wi‑Fi.';
  }
}
