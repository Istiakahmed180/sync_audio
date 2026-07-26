import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'services/audio_codec.dart';
import 'services/crash_reporter.dart';
import 'services/desktop_tray_service.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await CrashReporter.initialize();
      await OpusRuntime.initialize();
      await DesktopTrayService.initialize();
      runApp(const SyncAudioApp());
    },
    (error, stack) {
      unawaited(CrashReporter.record(error, stack));
    },
  );
}
