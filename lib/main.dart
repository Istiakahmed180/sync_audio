import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'app/app.dart';
import 'services/audio_codec.dart';
import 'services/crash_reporter.dart';
import 'services/desktop_tray_service.dart';
import 'services/firebase_telemetry.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      await SentryFlutter.init(
        (options) {
          options.dsn =
              'https://c8831ae7d7b88b31fa7534a25ea67b05@o4511810748481536.ingest.us.sentry.io/4511810760540160';
          options.sendDefaultPii = false;
          options.enableLogs = true;
          options.tracesSampleRate = 0.1;
          options.replay.sessionSampleRate = 0.1;
          options.replay.onErrorSampleRate = 1.0;
        },
        appRunner: () async {
          WidgetsFlutterBinding.ensureInitialized();
          await FirebaseTelemetry.initialize();
          await CrashReporter.initialize();
          await OpusRuntime.initialize();
          await DesktopTrayService.initialize();
          runApp(SentryWidget(child: const SyncAudioApp()));
        },
      );
    },
    (error, stack) {
      unawaited(CrashReporter.record(error, stack));
    },
  );
}
