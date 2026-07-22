import 'package:flutter/material.dart';

class NetworkDiagnosticsCard extends StatelessWidget {
  const NetworkDiagnosticsCard({
    required this.diagnostics,
    required this.isActive,
    super.key,
  });

  final Map<String, Object> diagnostics;
  final bool isActive;

  num _number(String key, [String? fallback]) {
    final value =
        diagnostics[key] ?? (fallback == null ? null : diagnostics[fallback]);
    return value is num ? value : 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasReceiverMetrics = diagnostics['metricsScope'] == 'receiver';
    final rttMs = _number('roundTripTimeMicros') / 1000;
    final loss = hasReceiverMetrics
        ? _number('packetLossPercent').toDouble()
        : null;
    final underruns = hasReceiverMetrics
        ? _number('packetUnderrunCount', 'underruns').toInt()
        : null;
    final overruns = hasReceiverMetrics
        ? _number('packetOverrunCount', 'overruns').toInt()
        : null;
    final currentPackets = hasReceiverMetrics
        ? _number('currentJitterBufferPackets', 'bufferPackets').toInt()
        : null;
    final targetBufferMs = hasReceiverMetrics
        ? _number('targetJitterBufferMicros', 'targetBufferMicros') / 1000
        : null;
    final quality = _quality(
      isActive: isActive,
      rttMs: rttMs,
      packetLoss: loss ?? 0,
      underruns: underruns ?? 0,
      hasReceiverMetrics: hasReceiverMetrics,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.network_check_rounded, color: quality.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Network health',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _QualityBadge(quality: quality),
              ],
            ),
            const SizedBox(height: 8),
            Text(quality.message),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricTile(label: 'Latency', value: _formatMs(rttMs)),
                _MetricTile(
                  label: 'Packet loss',
                  value: loss == null
                      ? 'Receiver data pending'
                      : '${loss.toStringAsFixed(1)}%',
                ),
                _MetricTile(
                  label: 'Buffer',
                  value: currentPackets == null
                      ? 'Receiver data pending'
                      : '$currentPackets pkts',
                ),
                _MetricTile(
                  label: 'Target',
                  value: targetBufferMs == null
                      ? 'Receiver data pending'
                      : _formatMs(targetBufferMs),
                ),
                _MetricTile(
                  label: 'Underruns',
                  value: underruns?.toString() ?? 'Receiver data pending',
                ),
                _MetricTile(
                  label: 'Overruns',
                  value: overruns?.toString() ?? 'Receiver data pending',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  _NetworkQuality _quality({
    required bool isActive,
    required num rttMs,
    required double packetLoss,
    required int underruns,
    required bool hasReceiverMetrics,
  }) {
    if (!isActive) {
      return const _NetworkQuality(
        label: 'Idle',
        message: 'Start audio to monitor the live network path.',
        color: Colors.grey,
      );
    }
    if (!hasReceiverMetrics) {
      return const _NetworkQuality(
        label: 'Waiting',
        message: 'Waiting for live Receiver diagnostics.',
        color: Colors.blueGrey,
      );
    }
    if (packetLoss >= 2 || underruns >= 5 || rttMs >= 120) {
      return const _NetworkQuality(
        label: 'Poor',
        message:
            'Audio may stutter. Move devices closer to the router or use 5 GHz Wi‑Fi.',
        color: Colors.red,
      );
    }
    if (packetLoss > 0 || underruns > 0 || rttMs >= 60) {
      return const _NetworkQuality(
        label: 'Fair',
        message:
            'The stream is usable, but the network has some timing variation.',
        color: Colors.orange,
      );
    }
    return const _NetworkQuality(
      label: 'Excellent',
      message: 'The audio network path looks healthy.',
      color: Colors.green,
    );
  }

  String _formatMs(num value) {
    if (value <= 0) return '—';
    return '${value.round()} ms';
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.quality});

  final _NetworkQuality quality;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: quality.color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        quality.label,
        style: TextStyle(color: quality.color, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 92),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    ),
  );
}

class _NetworkQuality {
  const _NetworkQuality({
    required this.label,
    required this.message,
    required this.color,
  });

  final String label;
  final String message;
  final Color color;
}
