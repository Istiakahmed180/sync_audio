import 'package:flutter/material.dart';
import 'package:flutter_driver/driver_extension.dart';

import 'app/app.dart';
import 'services/audio_codec.dart';
import 'services/desktop_tray_service.dart';

Future<void> main() async {
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();
  await OpusRuntime.initialize();
  await DesktopTrayService.initialize();
  runApp(const SyncAudioApp());
}
