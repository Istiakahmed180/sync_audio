import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_audio/app/app.dart';
import 'package:sync_audio/features/host/controllers/host_controller.dart';
import 'package:sync_audio/features/host/views/host_view.dart';
import 'package:sync_audio/features/receiver/controllers/receiver_controller.dart';
import 'package:sync_audio/features/receiver/views/receiver_view.dart';
import 'package:sync_audio/features/settings/controllers/settings_controller.dart';
import 'package:sync_audio/features/settings/views/settings_view.dart';

import 'phase2_test.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });
  tearDown(() => Get.reset());

  testWidgets('home screen starts successfully', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_complete': true,
    });
    await tester.pumpWidget(const SyncAudioApp());
    await tester.pumpAndSettle();
    expect(find.text('Sync Audio'), findsOneWidget);
    expect(find.text('Host Device'), findsOneWidget);
  });

  testWidgets('host screen displays connection setup', (tester) async {
    final service = FakeConnectionService();
    Get.put(HostController(connectionService: service));
    await tester.pumpWidget(const GetMaterialApp(home: HostView()));
    await tester.pumpAndSettle();
    expect(find.text('Receiver IP address'), findsOneWidget);
    expect(find.text('Receiver pairing code (required)'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.text('System audio'), findsOneWidget);
    expect(find.text('Send Test Message'), findsNothing);
  });

  testWidgets('receiver screen displays server controls', (tester) async {
    final service = FakeConnectionService();
    Get.put(ReceiverController(connectionService: service));
    await tester.pumpWidget(const GetMaterialApp(home: ReceiverView()));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Start Receiver'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Stop Receiver'), findsOneWidget);
    expect(find.text('Share with Host'), findsOneWidget);
  });

  testWidgets('settings screen displays all sections and schedule controls', (
    tester,
  ) async {
    Get.put(SettingsController());
    await tester.pumpWidget(const GetMaterialApp(home: SettingsView()));
    await tester.pumpAndSettle();

    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Scheduled streaming'), findsOneWidget);

    await tester.tap(find.text('Scheduled streaming'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Start time'), findsOneWidget);
    expect(find.text('Stop time'), findsOneWidget);
    expect(find.text('8:00 AM'), findsOneWidget);
    expect(find.text('10:00 PM'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('About'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
  });
}
