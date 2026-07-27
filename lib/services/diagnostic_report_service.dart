import 'dart:convert';

import 'package:share_plus/share_plus.dart';

import 'crash_reporter.dart';

enum DiagnosticReportFormat { json, text }

class DiagnosticReportService {
  static Future<void> share({
    required String scope,
    required Map<String, Object> diagnostics,
    Map<String, Map<String, Object>> receiverDiagnostics =
        const <String, Map<String, Object>>{},
    String? networkInfo,
    Map<String, Object> deviceInfo = const <String, Object>{},
    DiagnosticReportFormat format = DiagnosticReportFormat.json,
  }) async {
    final crashReports = await CrashReporter.recentReports();
    final report = <String, Object>{
      'app': 'SyncMesh Audio',
      'scope': scope,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'diagnostics': _sanitize(diagnostics),
      if (_metricSummary(diagnostics).isNotEmpty)
        'metrics': _metricSummary(diagnostics),
      if (networkInfo != null && networkInfo.isNotEmpty)
        'network': networkInfo,
      if (deviceInfo.isNotEmpty) 'device': _sanitize(deviceInfo),
      if (receiverDiagnostics.isNotEmpty)
        'receivers': {
          for (final entry in receiverDiagnostics.entries)
            entry.key: _sanitize(entry.value),
        },
      if (crashReports.isNotEmpty) 'recentCrashes': crashReports,
    };
    final content = format == DiagnosticReportFormat.json
        ? const JsonEncoder.withIndent('  ').convert(report)
        : _toText(report);
    await Share.share(
      content,
      subject: 'SyncMesh Audio diagnostic report ($scope)',
    );
  }

  static Map<String, Object> _metricSummary(Map<String, Object> values) {
    num? number(String key, [String? fallback]) {
      final value = values[key] ?? (fallback == null ? null : values[fallback]);
      return value is num ? value : null;
    }

    final summary = <String, Object>{};
    final rtt = number('roundTripTimeMicros');
    final jitter = number('networkJitterMicros');
    final loss = number('packetLossPercent');
    final buffer = number('currentJitterBufferPackets', 'bufferPackets');
    final bufferMs = number('bufferedDurationMicros');
    if (rtt != null) summary['pingMs'] = rtt / 1000;
    if (jitter != null) summary['jitterMs'] = jitter / 1000;
    if (loss != null) summary['packetLossPercent'] = loss;
    if (buffer != null) summary['bufferPackets'] = buffer;
    if (bufferMs != null) summary['bufferMs'] = bufferMs / 1000;
    return summary;
  }

  static Object _sanitize(Object value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': _sanitize(entry.value as Object),
      };
    }
    if (value is Iterable) {
      return value.map((item) => _sanitize(item as Object)).toList();
    }
    if (value is num || value is String || value is bool) return value;
    return value.toString();
  }

  static String _toText(Map<String, Object> report) {
    final buffer = StringBuffer()
      ..writeln('SyncMesh Audio diagnostic report')
      ..writeln('Scope: ${report['scope']}')
      ..writeln('Generated: ${report['generatedAt']}')
      ..writeln();
    _writeSection(buffer, 'Local diagnostics', report['diagnostics']);
    if (report['metrics'] != null) {
      buffer.writeln();
      _writeSection(buffer, 'Metrics summary', report['metrics']);
    }
    if (report['network'] != null) {
      buffer.writeln();
      _writeSection(buffer, 'Network', report['network']);
    }
    if (report['device'] != null) {
      buffer.writeln();
      _writeSection(buffer, 'Device', report['device']);
    }
    final receivers = report['receivers'];
    if (receivers is Map) {
      for (final entry in receivers.entries) {
        buffer.writeln();
        _writeSection(buffer, 'Receiver: ${entry.key}', entry.value);
      }
    }
    final crashes = report['recentCrashes'];
    if (crashes is Iterable && crashes.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Recent crashes');
      for (final crash in crashes) {
        buffer.writeln('  $crash');
      }
    }
    return buffer.toString();
  }

  static void _writeSection(StringBuffer buffer, String title, Object? value) {
    buffer.writeln(title);
    if (value is Map) {
      for (final entry in value.entries) {
        buffer.writeln('  ${entry.key}: ${entry.value}');
      }
    } else {
      buffer.writeln('  $value');
    }
  }
}
