/// Shared clock-offset and drift estimation for synchronized playback.
/// Transport-specific code sends requests and supplies timestamps; this class
/// owns the filtering and bounded drift calculation.
abstract class SynchronizationService {
  Future<void> synchronize();
  Future<void> stop();
  bool get isSynchronizing;

  ClockSynchronizationEstimate recordSample({
    required String sessionId,
    required int sentAtMicros,
    required int receivedAtMicros,
    required int remoteTimestampMicros,
  });

  void resetSession(String sessionId);
}

class ClockSynchronizationEstimate {
  const ClockSynchronizationEstimate({
    required this.roundTripTimeMicros,
    required this.offsetMicros,
    required this.driftPpm,
  });

  final int roundTripTimeMicros;
  final int offsetMicros;
  final int driftPpm;
}

class ClockSynchronizationService implements SynchronizationService {
  final Map<String, _ClockEstimate> _estimates = <String, _ClockEstimate>{};
  bool _isSynchronizing = false;

  @override
  bool get isSynchronizing => _isSynchronizing;

  @override
  Future<void> synchronize() async {
    _estimates.clear();
    _isSynchronizing = true;
  }

  @override
  Future<void> stop() async {
    _isSynchronizing = false;
    _estimates.clear();
  }

  @override
  void resetSession(String sessionId) => _estimates.remove(sessionId);

  @override
  ClockSynchronizationEstimate recordSample({
    required String sessionId,
    required int sentAtMicros,
    required int receivedAtMicros,
    required int remoteTimestampMicros,
  }) {
    final rtt = (receivedAtMicros - sentAtMicros)
        .clamp(0, 60 * 1000000)
        .toInt();
    final sampleOffset =
        ((remoteTimestampMicros - sentAtMicros) +
            (remoteTimestampMicros - receivedAtMicros)) ~/
        2;
    final previous = _estimates[sessionId];
    final isNewBest = previous == null || rtt < previous.bestRoundTripMicros;
    final comparisonRtt = previous?.bestRoundTripMicros ?? rtt;
    final alpha = previous == null
        ? 1.0
        : isNewBest
        ? 0.65
        : rtt <= comparisonRtt + 2000
        ? 0.25
        : 0.06;
    final offset = previous == null
        ? sampleOffset
        : previous.offsetMicros +
              ((sampleOffset - previous.offsetMicros) * alpha).round();
    final elapsed = previous == null
        ? 0
        : receivedAtMicros - previous.lastReceivedAtMicros;
    final drift = elapsed <= 0
        ? previous?.driftPpm ?? 0
        : (((offset - previous!.offsetMicros) * 1000000) / elapsed)
              .round()
              .clamp(-5000, 5000)
              .toInt();
    _estimates[sessionId] = _ClockEstimate(
      bestRoundTripMicros: isNewBest ? rtt : comparisonRtt,
      offsetMicros: offset,
      driftPpm: drift,
      lastReceivedAtMicros: receivedAtMicros,
    );
    return ClockSynchronizationEstimate(
      roundTripTimeMicros: rtt,
      offsetMicros: offset,
      driftPpm: drift,
    );
  }
}

class _ClockEstimate {
  const _ClockEstimate({
    required this.bestRoundTripMicros,
    required this.offsetMicros,
    required this.driftPpm,
    required this.lastReceivedAtMicros,
  });

  final int bestRoundTripMicros;
  final int offsetMicros;
  final int driftPpm;
  final int lastReceivedAtMicros;
}
