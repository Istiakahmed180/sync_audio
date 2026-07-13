enum AudioStreamStatus { idle, starting, streaming, receiving, stopped, error }

extension AudioStreamStatusLabel on AudioStreamStatus {
  String get label => switch (this) {
    AudioStreamStatus.idle => 'Idle',
    AudioStreamStatus.starting => 'Starting',
    AudioStreamStatus.streaming => 'Streaming',
    AudioStreamStatus.receiving => 'Receiving',
    AudioStreamStatus.stopped => 'Stopped',
    AudioStreamStatus.error => 'Error',
  };
}
