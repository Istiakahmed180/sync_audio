import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_audio/app/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app opens and exposes the main role selection', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'onboarding_complete': true,
    });
    await tester.pumpWidget(const SyncAudioApp());
    await tester.pumpAndSettle();

    expect(find.text('Sync Audio'), findsOneWidget);
    expect(find.text('Host Device'), findsOneWidget);
    expect(find.text('Receiver Device'), findsOneWidget);
  });
}
