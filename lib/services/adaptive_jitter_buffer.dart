import 'dart:typed_data';

import 'latency_metrics.dart';

class JitterAudioPacket {
  const JitterAudioPacket({
    required this.sequence,
    required this.timestampMicros,
    required this.payload,
    required this.arrivalMicros,
  });

  final int sequence;
  final int timestampMicros;
  final Uint8List payload;
  final int arrivalMicros;
}

class AdaptiveJitterBuffer {
  AdaptiveJitterBuffer({this.mode = LatencyMode.balanced, this.enabled = true})
    : _config = LatencyModeConfig.forMode(mode);

  LatencyMode mode;
  bool enabled;
  LatencyModeConfig _config;
  final Map<int, JitterAudioPacket> _packets = <int, JitterAudioPacket>{};
  int? nextSequence;
  int? _lastArrivalMicros;
  int _jitterMicros = 0;
  int _missingSinceMicros = 0;
  int underruns = 0;
  int overruns = 0;
  int reorders = 0;
  int latePackets = 0;

  int _minTimestamp = 0;
  int _maxTimestamp = 0;
  bool _haveTimestamps = false;

  int get length => _packets.length;
  int get bufferedDurationMicros {
    if (_packets.length < 2) return 0;
    return _maxTimestamp - _minTimestamp;
  }

  int get targetDelayMicros => _config.normalMicros + _jitterMicros * 2;
  int get targetBufferMicros =>
      targetDelayMicros.clamp(_config.minimumMicros, _config.maximumMicros);
  int get jitterMicros => _jitterMicros;

  void configure({required LatencyMode mode, required bool enabled}) {
    this.mode = mode;
    this.enabled = enabled;
    _config = LatencyModeConfig.forMode(mode);
  }

  bool add(JitterAudioPacket packet) {
    final previous = _lastArrivalMicros;
    if (previous != null) {
      final interval = packet.arrivalMicros - previous;
      final expected = 20000;
      final deviation = (interval - expected).abs();
      _jitterMicros = _jitterMicros == 0
          ? deviation
          : ((_jitterMicros * 7) + deviation) ~/ 8;
    }
    _lastArrivalMicros = packet.arrivalMicros;
    if (nextSequence != null && _isBehind(packet.sequence, nextSequence!)) {
      latePackets++;
      return false;
    }
    if (_packets.containsKey(packet.sequence)) return false;
    if (nextSequence != null && packet.sequence != nextSequence) reorders++;
    _packets[packet.sequence] = packet;
    final ts = packet.timestampMicros;
    if (!_haveTimestamps) {
      _minTimestamp = ts;
      _maxTimestamp = ts;
      _haveTimestamps = true;
    } else {
      if (ts < _minTimestamp) _minTimestamp = ts;
      if (ts > _maxTimestamp) _maxTimestamp = ts;
    }
    while (_packets.length > 256) {
      _removeOldest();
      overruns++;
    }
    return true;
  }

  JitterAudioPacket? takeReady(int nowMicros) {
    if (nextSequence == null && _packets.isNotEmpty) {
      nextSequence = _oldestSequence();
    }
    final sequence = nextSequence;
    if (sequence == null) return null;
    final packet = _packets[sequence];
    if (packet == null) {
      if (_packets.isEmpty) {
        _missingSinceMicros = 0;
        return null;
      }
      _missingSinceMicros = _missingSinceMicros == 0
          ? nowMicros
          : _missingSinceMicros;
      // Stable mode gives Wi-Fi packets more time to arrive out of order
      // before advancing past a missing sequence number. This is useful when
      // the receiver also forwards audio over Bluetooth.
      final timeout = !enabled
          ? 10000
          : switch (mode) {
              LatencyMode.stable => 80000,
              LatencyMode.balanced => 50000,
              LatencyMode.ultraLow => 30000,
            };
      if (nowMicros - _missingSinceMicros < timeout) return null;
      underruns++;
      nextSequence = _oldestSequence();
      _missingSinceMicros = 0;
      return null;
    }
    _missingSinceMicros = 0;
    if (enabled && nowMicros < packet.timestampMicros) return null;
    _packets.remove(sequence);
    _onPacketRemoved(packet.timestampMicros);
    nextSequence = (sequence + 1) & 0xFFFFFFFF;
    return packet;
  }

  void _onPacketRemoved(int ts) {
    if (_haveTimestamps && (ts == _minTimestamp || ts == _maxTimestamp)) {
      _recalcTimestamps();
    }
  }

  void _recalcTimestamps() {
    if (_packets.isEmpty) {
      _haveTimestamps = false;
      return;
    }
    _minTimestamp = _packets.values
        .map((p) => p.timestampMicros)
        .reduce((a, b) => a < b ? a : b);
    _maxTimestamp = _packets.values
        .map((p) => p.timestampMicros)
        .reduce((a, b) => a > b ? a : b);
  }

  void reset() {
    _packets.clear();
    nextSequence = null;
    _lastArrivalMicros = null;
    _jitterMicros = 0;
    _missingSinceMicros = 0;
    _haveTimestamps = false;
    _minTimestamp = 0;
    _maxTimestamp = 0;
    underruns = 0;
    overruns = 0;
    reorders = 0;
    latePackets = 0;
  }

  int _oldestSequence() =>
      _packets.keys.reduce((a, b) => _isBehind(a, b) ? a : b);

  void _removeOldest() {
    final oldestSeq = _oldestSequence();
    final packet = _packets[oldestSeq];
    _packets.remove(oldestSeq);
    if (packet != null) _onPacketRemoved(packet.timestampMicros);
  }

  bool _isBehind(int sequence, int reference) {
    final difference = (reference - sequence) & 0xFFFFFFFF;
    return difference != 0 && difference < 0x80000000;
  }
}
