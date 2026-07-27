enum ConnectionActivityType {
  connected,
  disconnected,
  reconnecting,
  error,
  networkChanged,
}

class ConnectionActivity {
  const ConnectionActivity({
    required this.type,
    required this.receiverName,
    required this.address,
    required this.timestamp,
    this.details,
  });

  final ConnectionActivityType type;
  final String receiverName;
  final String address;
  final DateTime timestamp;
  final String? details;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'receiverName': receiverName,
    'address': address,
    'timestamp': timestamp.toIso8601String(),
    if (details != null) 'details': details,
  };

  factory ConnectionActivity.fromJson(Map<String, dynamic> json) {
    return ConnectionActivity(
      type: ConnectionActivityType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => ConnectionActivityType.error,
      ),
      receiverName: json['receiverName'] as String? ?? 'Receiver',
      address: json['address'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      details: json['details'] as String?,
    );
  }
}
