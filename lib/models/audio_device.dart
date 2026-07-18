class AudioDevice {
  const AudioDevice({
    required this.id,
    required this.name,
    required this.ipAddress,
    required this.port,
    this.pairingCode,
    this.isConnected = false,
    this.latencyMs = 0,
  });

  final String id;
  final String name;
  final String ipAddress;
  final int port;
  final String? pairingCode;
  final bool isConnected;
  final int latencyMs;

  AudioDevice copyWith({
    String? id,
    String? name,
    String? ipAddress,
    int? port,
    String? pairingCode,
    bool? isConnected,
    int? latencyMs,
  }) => AudioDevice(
    id: id ?? this.id,
    name: name ?? this.name,
    ipAddress: ipAddress ?? this.ipAddress,
    port: port ?? this.port,
    pairingCode: pairingCode ?? this.pairingCode,
    isConnected: isConnected ?? this.isConnected,
    latencyMs: latencyMs ?? this.latencyMs,
  );

  @override
  bool operator ==(Object other) =>
      other is AudioDevice &&
      id == other.id &&
      name == other.name &&
      ipAddress == other.ipAddress &&
      port == other.port &&
      pairingCode == other.pairingCode &&
      isConnected == other.isConnected &&
      latencyMs == other.latencyMs;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    ipAddress,
    port,
    pairingCode,
    isConnected,
    latencyMs,
  );

  @override
  String toString() =>
      'AudioDevice(id: $id, name: $name, ipAddress: $ipAddress, port: $port, pairingCode: $pairingCode, isConnected: $isConnected, latencyMs: $latencyMs)';
}
