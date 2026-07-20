import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bindings/initial_binding.dart';
import 'routes/app_pages.dart';
import 'routes/app_routes.dart';
import 'theme/app_theme.dart';

class SyncAudioApp extends StatelessWidget {
  const SyncAudioApp({super.key});

  Future<(bool, ThemeMode)> _loadStartupConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    final themeModeStr = prefs.getString('theme_mode') ?? 'system';
    final themeMode = switch (themeModeStr) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return (onboardingComplete, themeMode);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(bool, ThemeMode)>(
      future: _loadStartupConfig(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Center(child: CircularProgressIndicator.adaptive()),
            ),
          );
        }

        final (onboardingComplete, themeMode) = snapshot.data!;

        final initialRoute = onboardingComplete
            ? AppRoutes.home
            : AppRoutes.onboarding;

        return GetMaterialApp(
          title: 'Sync Audio',
          debugShowCheckedModeBanner: false,
          initialRoute: initialRoute,
          initialBinding: InitialBinding(),
          getPages: AppPages.pages,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: themeMode,
        );
      },
    );
  }
}
