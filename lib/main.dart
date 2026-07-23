import 'package:flutter/material.dart';

import 'app/app.dart';
import 'services/audio_codec.dart';
import 'services/desktop_tray_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OpusRuntime.initialize();
  await DesktopTrayService.initialize();
  runApp(const SyncAudioApp());
}
