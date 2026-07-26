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
    DiagnosticReportFormat format = DiagnosticReportFormat.json,
  }) async {
    final crashReports = await CrashReporter.recentReports();
    final report = <String, Object>{
      'app': 'SyncMesh Audio',
      'scope': scope,
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
      'diagnostics': _sanitize(diagnostics),
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
