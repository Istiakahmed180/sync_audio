import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:sync_audio/app/app.dart';

void main() {
  testWidgets('home screen starts successfully', (tester) async {
    await tester.pumpWidget(const SyncAudioApp());
    expect(find.text('Sync Audio'), findsOneWidget);
    expect(find.text('Host Device'), findsOneWidget);
  });

  testWidgets('host card navigates and streaming starts disabled', (
    tester,
  ) async {
    await tester.pumpWidget(const SyncAudioApp());
    await tester.tap(find.text('Host Device'));
    await tester.pumpAndSettle();
    expect(find.text('Host Device'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Start Streaming'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start Streaming'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('receiver start updates status', (tester) async {
    await tester.pumpWidget(const SyncAudioApp());
    await tester.tap(find.text('Receiver Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Start Receiver'));
    await tester.pump();
    expect(find.text('Connected'), findsOneWidget);
    Get.reset();
  });
}
