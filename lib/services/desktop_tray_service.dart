import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps the desktop process alive when the user closes the window.
///
/// The tray is intentionally desktop-only. Android already uses foreground
/// services and its persistent media notification for background streaming.
class DesktopTrayService with WindowListener, TrayListener {
  DesktopTrayService._();

  static final DesktopTrayService instance = DesktopTrayService._();
  bool _quitting = false;

  static bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<void> initialize() async {
    if (!isSupported) return;
    await windowManager.ensureInitialized();
    instance._registerListeners();
    await instance._configureTray();
    await windowManager.setPreventClose(true);
  }

  void _registerListeners() {
    windowManager.addListener(this);
    trayManager.addListener(this);
  }

  Future<void> _configureTray() async {
    try {
      final iconPath = _findIconPath();
      if (iconPath != null) {
        await trayManager.setIcon(iconPath);
      }
      await trayManager.setToolTip('Sync Audio');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show_window', label: 'Show Sync Audio'),
            MenuItem.separator(),
            MenuItem(key: 'exit_app', label: 'Quit Sync Audio'),
          ],
        ),
      );
    } catch (_) {
      // Tray support is best-effort. The desktop app remains usable if the
      // host OS lacks a compatible tray implementation.
    }
  }

  String? _findIconPath() {
    final candidates = <String>[
      if (Platform.isWindows) 'windows/runner/resources/app_icon.ico',
      'assets/branding/sync_audio_app_icon.png',
      if (Platform.isMacOS)
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png',
      if (Platform.isLinux) 'linux/icons/sync_audio.png',
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) return file.absolute.path;
    }
    return null;
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    // Hide instead of destroying the Flutter engine. Active TCP/UDP audio
    // streams therefore continue while the app is in the tray.
    windowManager.hide();
    windowManager.setSkipTaskbar(true);
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      _showWindow();
    } else if (menuItem.key == 'exit_app') {
      _quit();
    }
  }

  Future<void> _showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quit() async {
    _quitting = true;
    await trayManager.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }
}
