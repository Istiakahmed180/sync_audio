import 'dart:io';
import 'dart:async';

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
  bool _iconApplied = false;
  Future<void> Function(String action)? _actionHandler;
  bool _isStreaming = false;
  bool _isMuted = false;
  int _receiverCount = 0;

  static bool get isSupported =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static Future<void> initialize() async {
    if (!isSupported) return;
    await windowManager.ensureInitialized();
    // Initializes the native taskbar COM object used by setSkipTaskbar. The
    // window_manager plugin crashes (null taskbar pointer) if hidden/show or
    // skip-taskbar APIs run before this. Some desktops (kiosk shells) have no
    // usable taskbar, so this must stay best-effort.
    try {
      await windowManager.waitUntilReadyToShow();
    } catch (_) {
      // Tray support is best-effort; the window can still hide without it.
    }
    instance._registerListeners();
    await instance._configureTray();
    await windowManager.setPreventClose(true);
  }

  static void setActionHandler(Future<void> Function(String action)? handler) {
    instance._actionHandler = handler;
  }

  static Future<void> updateHostState({
    required bool isStreaming,
    required bool isMuted,
    required int receiverCount,
  }) async {
    if (!isSupported) return;
    // The host pushes its state on every session/ping update (about every two
    // seconds). Rebuilding the tray icon and context menu that often made the
    // open menu flicker and look like it was toggling on/off, so only touch
    // the tray when something actually changed.
    if (instance._isStreaming == isStreaming &&
        instance._isMuted == isMuted &&
        instance._receiverCount == receiverCount) {
      return;
    }
    instance
      .._isStreaming = isStreaming
      .._isMuted = isMuted
      .._receiverCount = receiverCount;
    await instance._configureTray();
  }

  void _registerListeners() {
    windowManager.addListener(this);
    trayManager.addListener(this);
  }

  Future<void> _configureTray() async {
    try {
      if (!_iconApplied) {
        final iconPath = _findIconPath();
        if (iconPath != null) {
          await trayManager.setIcon(iconPath);
          _iconApplied = true;
        }
      }
      await trayManager.setToolTip('SyncMesh Audio');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show_window', label: 'Show SyncMesh Audio'),
            MenuItem.separator(),
            MenuItem(
              label: _isStreaming
                  ? 'Streaming • $_receiverCount Receiver(s)'
                  : 'Ready • $_receiverCount Receiver(s)',
              disabled: true,
            ),
            MenuItem(
              key: _isStreaming ? 'pause_stream' : 'resume_stream',
              label: _isStreaming ? 'Pause streaming' : 'Resume streaming',
            ),
            MenuItem(
              key: 'toggle_mute',
              label: _isMuted ? 'Unmute all Receivers' : 'Mute all Receivers',
            ),
            MenuItem.separator(),
            MenuItem(key: 'exit_app', label: 'Quit SyncMesh Audio'),
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
      if (Platform.isWindows)
        // A packaged Windows build ships Flutter assets under
        // <exe dir>/data/flutter_assets, not at the working directory. Use a
        // real .ico because the tray plugin loads it as a Windows icon.
        ..._bundledAssetCandidates('assets/branding/sync_audio_app_icon.ico'),
      if (Platform.isWindows) 'windows/runner/resources/app_icon.ico',
      if (Platform.isWindows)
        ..._bundledAssetCandidates('assets/branding/sync_audio_app_icon.png'),
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

  Iterable<String> _bundledAssetCandidates(String assetPath) sync* {
    try {
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      final separator = Platform.pathSeparator;
      yield '$executableDir$separator' 'data$separator'
          'flutter_assets$separator'
          '${assetPath.replaceAll('/', separator)}';
    } catch (_) {
      // Fall back to the working-directory candidates below.
    }
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    // Hide instead of destroying the Flutter engine. Active TCP/UDP audio
    // streams therefore continue while the app is in the tray.
    unawaited(windowManager.hide());
    unawaited(windowManager.setSkipTaskbar(true));
  }

  @override
  void onTrayIconMouseDown() {
    _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // tray_manager does not pop the context menu by itself; on Windows a
    // right-click only fires this callback, so the menu (including Quit) never
    // appeared until we explicitly asked for it.
    // `bringAppToFront` is deprecated but required on Windows: the native
    // TrackPopupMenu needs a foreground owner window, otherwise the menu stays
    // open and never dismisses when the user clicks elsewhere.
    // ignore: deprecated_member_use
    unawaited(trayManager.popUpContextMenu(bringAppToFront: true));
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'show_window') {
      _showWindow();
    } else if (menuItem.key == 'pause_stream' ||
        menuItem.key == 'resume_stream') {
      final handler = _actionHandler;
      if (handler != null) unawaited(handler(menuItem.key!));
    } else if (menuItem.key == 'toggle_mute') {
      final handler = _actionHandler;
      if (handler != null) unawaited(handler(menuItem.key!));
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
