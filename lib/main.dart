import 'package:flutter/material.dart';

import 'app/app.dart';
import 'services/audio_codec.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await OpusRuntime.initialize();
  runApp(const SyncAudioApp());
}
