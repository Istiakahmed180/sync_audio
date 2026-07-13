enum ControlConnectionStatus {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

extension ControlConnectionStatusLabel on ControlConnectionStatus {
  String get label => switch (this) {
    ControlConnectionStatus.disconnected => 'TCP offline',
    ControlConnectionStatus.connecting => 'TCP connecting',
    ControlConnectionStatus.connected => 'TCP connected',
    ControlConnectionStatus.reconnecting => 'TCP reconnecting',
    ControlConnectionStatus.error => 'TCP error',
  };
}

enum ReceiverSessionStatus {
  configured,
  synchronizing,
  connected,
  streaming,
  reconnecting,
  disconnected,
  error,
}

extension ReceiverSessionStatusLabel on ReceiverSessionStatus {
  String get label => switch (this) {
    ReceiverSessionStatus.configured => 'Configured',
    ReceiverSessionStatus.synchronizing => 'Synchronizing',
    ReceiverSessionStatus.connected => 'Connected',
    ReceiverSessionStatus.streaming => 'Streaming',
    ReceiverSessionStatus.reconnecting => 'Reconnecting',
    ReceiverSessionStatus.disconnected => 'Disconnected',
    ReceiverSessionStatus.error => 'Error',
  };
}

class ReceiverSession {
  const ReceiverSession({
    required this.id,
    required this.ipAddress,
    required this.port,
    this.status = ReceiverSessionStatus.configured,
    this.controlStatus = ControlConnectionStatus.disconnected,
    this.clockOffsetMicros = 0,
    this.playbackCalibrationMicros = 0,
    this.roundTripTimeMicros = 0,
    this.lastSyncMicros,
    this.reconnectAttempt = 0,
  });

  final String id;
  final String ipAddress;
  final int port;
  final ReceiverSessionStatus status;
  final ControlConnectionStatus controlStatus;
  final int clockOffsetMicros;
  final int playbackCalibrationMicros;
  final int roundTripTimeMicros;
  final int? lastSyncMicros;
  final int reconnectAttempt;

  ReceiverSession copyWith({
    String? id,
    String? ipAddress,
    int? port,
    ReceiverSessionStatus? status,
    ControlConnectionStatus? controlStatus,
    int? clockOffsetMicros,
    int? playbackCalibrationMicros,
    int? roundTripTimeMicros,
    int? lastSyncMicros,
    int? reconnectAttempt,
  }) => ReceiverSession(
    id: id ?? this.id,
    ipAddress: ipAddress ?? this.ipAddress,
    port: port ?? this.port,
    status: status ?? this.status,
    controlStatus: controlStatus ?? this.controlStatus,
    clockOffsetMicros: clockOffsetMicros ?? this.clockOffsetMicros,
    playbackCalibrationMicros:
        playbackCalibrationMicros ?? this.playbackCalibrationMicros,
    roundTripTimeMicros: roundTripTimeMicros ?? this.roundTripTimeMicros,
    lastSyncMicros: lastSyncMicros ?? this.lastSyncMicros,
    reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
  );

  @override
  bool operator ==(Object other) =>
      other is ReceiverSession &&
      id == other.id &&
      ipAddress == other.ipAddress &&
      port == other.port &&
      status == other.status &&
      controlStatus == other.controlStatus &&
      clockOffsetMicros == other.clockOffsetMicros &&
      playbackCalibrationMicros == other.playbackCalibrationMicros &&
      roundTripTimeMicros == other.roundTripTimeMicros &&
      lastSyncMicros == other.lastSyncMicros &&
      reconnectAttempt == other.reconnectAttempt;

  @override
  int get hashCode => Object.hash(
    id,
    ipAddress,
    port,
    status,
    controlStatus,
    clockOffsetMicros,
    playbackCalibrationMicros,
    roundTripTimeMicros,
    lastSyncMicros,
    reconnectAttempt,
  );
}
