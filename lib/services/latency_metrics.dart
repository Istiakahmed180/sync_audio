import 'dart:math' as math;

enum LatencyMode { ultraLow, balanced, stable }

extension LatencyModeLabel on LatencyMode {
  String get label => switch (this) {
    LatencyMode.ultraLow => 'Ultra Low',
    LatencyMode.balanced => 'Balanced',
    LatencyMode.stable => 'Stable',
  };
}

class LatencyModeConfig {
  const LatencyModeConfig({
    required this.minimumMicros,
    required this.normalMicros,
    required this.maximumMicros,
  });

  final int minimumMicros;
  final int normalMicros;
  final int maximumMicros;

  static LatencyModeConfig forMode(LatencyMode mode) => switch (mode) {
    LatencyMode.ultraLow => const LatencyModeConfig(
      minimumMicros: 50000,
      normalMicros: 60000,
      maximumMicros: 160000,
    ),
    LatencyMode.balanced => const LatencyModeConfig(
      minimumMicros: 80000,
      normalMicros: 120000,
      maximumMicros: 300000,
    ),
    LatencyMode.stable => const LatencyModeConfig(
      minimumMicros: 160000,
      normalMicros: 220000,
      maximumMicros: 500000,
    ),
  };
}

class LatencyMetricsSnapshot {
  const LatencyMetricsSnapshot({
    required this.captureStartTimestampMicros,
    required this.captureToEncodeMicros,
    required this.encodeMicros,
    required this.packetSendTimestampMicros,
    required this.packetArrivalTimestampMicros,
    required this.decryptMicros,
    required this.decodeMicros,
    required this.jitterBufferWaitingMicros,
    required this.scheduledPlaybackTimestampMicros,
    required this.playbackQueueDelayMicros,
    required this.estimatedTotalLatencyMicros,
    required this.roundTripTimeMicros,
    required this.packetLossPercent,
    required this.packetReorderCount,
    required this.packetUnderrunCount,
    required this.packetOverrunCount,
    required this.currentJitterBufferPackets,
    required this.targetJitterBufferMicros,
    required this.clockOffsetMicros,
    required this.clockDriftPpm,
    required this.appliedDriftCorrectionPpm,
    required this.receiverSynchronizationErrorMicros,
  });

  final int captureStartTimestampMicros;
  final int captureToEncodeMicros;
  final int encodeMicros;
  final int packetSendTimestampMicros;
  final int packetArrivalTimestampMicros;
  final int decryptMicros;
  final int decodeMicros;
  final int jitterBufferWaitingMicros;
  final int scheduledPlaybackTimestampMicros;
  final int playbackQueueDelayMicros;
  final int estimatedTotalLatencyMicros;
  final int roundTripTimeMicros;
  final double packetLossPercent;
  final int packetReorderCount;
  final int packetUnderrunCount;
  final int packetOverrunCount;
  final int currentJitterBufferPackets;
  final int targetJitterBufferMicros;
  final int clockOffsetMicros;
  final int clockDriftPpm;
  final int appliedDriftCorrectionPpm;
  final int receiverSynchronizationErrorMicros;

  Map<String, Object> toRedactedMap() => <String, Object>{
    'captureToEncodeMicros': captureToEncodeMicros,
    'encodeMicros': encodeMicros,
    'decryptMicros': decryptMicros,
    'decodeMicros': decodeMicros,
    'jitterBufferWaitingMicros': jitterBufferWaitingMicros,
    'estimatedTotalLatencyMicros': estimatedTotalLatencyMicros,
    'roundTripTimeMicros': roundTripTimeMicros,
    'packetLossPercent': packetLossPercent,
    'packetReorderCount': packetReorderCount,
    'packetUnderrunCount': packetUnderrunCount,
    'packetOverrunCount': packetOverrunCount,
    'currentJitterBufferPackets': currentJitterBufferPackets,
    'targetJitterBufferMicros': targetJitterBufferMicros,
    'clockOffsetMicros': clockOffsetMicros,
    'clockDriftPpm': clockDriftPpm,
    'appliedDriftCorrectionPpm': appliedDriftCorrectionPpm,
    'receiverSynchronizationErrorMicros': receiverSynchronizationErrorMicros,
  };
}

class LatencyMetricsTracker {
  final Stopwatch _clock = Stopwatch()..start();
  int _captureStart = 0;
  int _captureToEncode = 0;
  int _encode = 0;
  int _send = 0;
  int _arrival = 0;
  int _decrypt = 0;
  int _decode = 0;
  int _jitterWait = 0;
  int _scheduled = 0;
  int _queueDelay = 0;
  int _totalLatency = 0;
  int _rtt = 0;
  int _receivedPackets = 0;
  int _lostPackets = 0;
  int _reorders = 0;
  int _underruns = 0;
  int _overruns = 0;
  int _currentPackets = 0;
  int _targetBuffer = 120000;
  int _offset = 0;
  int _drift = 0;
  int _appliedCorrection = 0;
  int _syncError = 0;

  int get nowMicros => _clock.elapsedMicroseconds;

  void captureStarted() => _captureStart = nowMicros;

  void encoded(Duration duration) {
    _encode = _smooth(_encode, duration.inMicroseconds);
    _captureToEncode = _smooth(
      _captureToEncode,
      math.max(0, nowMicros - _captureStart),
    );
  }

  void packetSent() => _send = nowMicros;

  void packetArrived() {
    _arrival = nowMicros;
    _receivedPackets++;
  }

  void decrypted(Duration duration) =>
      _decrypt = _smooth(_decrypt, duration.inMicroseconds);

  void decoded(Duration duration) =>
      _decode = _smooth(_decode, duration.inMicroseconds);

  void scheduled({required int timestampMicros, required int waitingMicros}) {
    _scheduled = timestampMicros;
    _jitterWait = _smooth(_jitterWait, waitingMicros);
    _queueDelay = _smooth(
      _queueDelay,
      math.max(0, nowMicros - timestampMicros),
    );
    _totalLatency = _smooth(
      _totalLatency,
      math.max(0, nowMicros - _captureStart),
    );
  }

  void clockSample({required int rttMicros, required int offsetMicros}) {
    _rtt = _smooth(_rtt, rttMicros);
    _offset = offsetMicros;
  }

  void setBuffer({required int currentPackets, required int targetMicros}) {
    _currentPackets = currentPackets;
    _targetBuffer = targetMicros;
  }

  void setDrift({required int estimatedPpm, required int appliedPpm}) {
    _drift = estimatedPpm;
    _appliedCorrection = appliedPpm;
  }

  void setSynchronizationError(int errorMicros) => _syncError = errorMicros;
  void packetLost() => _lostPackets++;
  void packetReordered() => _reorders++;
  void packetUnderrun() => _underruns++;
  void packetOverrun() => _overruns++;

  LatencyMetricsSnapshot snapshot() => LatencyMetricsSnapshot(
    captureStartTimestampMicros: _captureStart,
    captureToEncodeMicros: _captureToEncode,
    encodeMicros: _encode,
    packetSendTimestampMicros: _send,
    packetArrivalTimestampMicros: _arrival,
    decryptMicros: _decrypt,
    decodeMicros: _decode,
    jitterBufferWaitingMicros: _jitterWait,
    scheduledPlaybackTimestampMicros: _scheduled,
    playbackQueueDelayMicros: _queueDelay,
    estimatedTotalLatencyMicros: _totalLatency,
    roundTripTimeMicros: _rtt,
    packetLossPercent: _receivedPackets + _lostPackets == 0
        ? 0
        : _lostPackets * 100 / (_receivedPackets + _lostPackets),
    packetReorderCount: _reorders,
    packetUnderrunCount: _underruns,
    packetOverrunCount: _overruns,
    currentJitterBufferPackets: _currentPackets,
    targetJitterBufferMicros: _targetBuffer,
    clockOffsetMicros: _offset,
    clockDriftPpm: _drift,
    appliedDriftCorrectionPpm: _appliedCorrection,
    receiverSynchronizationErrorMicros: _syncError,
  );

  int _smooth(int oldValue, int newValue) =>
      oldValue == 0 ? newValue : ((oldValue * 7) + newValue) ~/ 8;
}
