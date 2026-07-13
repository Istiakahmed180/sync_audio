enum ConnectionStatus {
  disconnected,
  startingServer,
  waiting,
  connecting,
  connected,
  stopped,
  error,
}

extension ConnectionStatusLabel on ConnectionStatus {
  String get label => switch (this) {
    ConnectionStatus.disconnected => 'Disconnected',
    ConnectionStatus.startingServer => 'Starting',
    ConnectionStatus.waiting => 'Waiting',
    ConnectionStatus.connecting => 'Connecting',
    ConnectionStatus.connected => 'Connected',
    ConnectionStatus.stopped => 'Stopped',
    ConnectionStatus.error => 'Error',
  };
}
