import 'dart:async';

import 'services/device_performance.dart';
import 'services/browser_features.dart';
import 'services/android_network_trust.dart';
import 'package:flutter/foundation.dart';
import 'core/app_platform.dart';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/platform_ui.dart';
import 'screens/update_screen.dart';
import 'services/accessibility_service.dart';
import 'services/app_links.dart';
import 'services/download_manager.dart';
import 'services/device_bridge.dart';

SemanticsHandle? _webSemantics;

Future<void> _showWindowsShell() async {
  // Runs after runApp so the first Flutter frame (which releases the native
  // `Show` gate) is never blocked by a slow/hung window_manager plugin.
  try {
    await windowManager.ensureInitialized().timeout(const Duration(seconds: 8));
    const options = WindowOptions(
      size: Size(1440, 900),
      minimumSize: Size(1000, 650),
      center: true,
      backgroundColor: Color(0xFF080A0F),
      title: 'MBNMovie',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager
        .waitUntilReadyToShow(options, () async {
          await windowManager.show();
          await windowManager.focus();
        })
        .timeout(const Duration(seconds: 10));
  } catch (_) {
    // Last resort: never leave a hidden/white window behind.
    try {
      await windowManager.show();
    } catch (_) {}
  }
}

Future<void> _initializeWebAfterFirstFrame() async {
  // Browser storage and platform channels are allowed to be slow on Safari.
  // They refine the already-visible UI instead of delaying its first frame.
  try {
    await AccessibilityService.instance.initialize().timeout(
      const Duration(seconds: 8),
    );
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS Safari's semantics DOM can sit above Flutter's gesture arena while
  // the PWA restores its session. Keep ordinary touch events on Flutter and
  // expose semantics on desktop/assistive browsers.
  if (kIsWeb && !BrowserFeatures.isAppleMobile) {
    _webSemantics ??= SemanticsBinding.instance.ensureSemantics();
  }
  // A missing libmpv must break only video playback, never the whole window.
  try {
    MediaKit.ensureInitialized();
  } catch (_) {}
  DeviceBridge.initialize();
  if (kIsWeb) {
    DevicePerformance.configureWeb();
    runApp(const MbnmovieApp());
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_initializeWebAfterFirstFrame()),
    );
    return;
  }
  // Each pre-run init is bounded: a hung plugin/storage on Windows 10 must
  // fall through to runApp instead of leaving a blank white window.
  try {
    await initializeDeviceLayout().timeout(const Duration(seconds: 8));
  } catch (_) {}
  try {
    await DevicePerformance.initialize().timeout(const Duration(seconds: 8));
  } catch (_) {}
  try {
    await AndroidNetworkTrust.initialize().timeout(const Duration(seconds: 8));
  } catch (_) {}
  try {
    await AccessibilityService.instance.initialize().timeout(
      const Duration(seconds: 8),
    );
  } catch (_) {}
  if (isAndroidTv) {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
  }
  if (Platform.isWindows) {
    // Show the Flutter UI first; the window shell follows asynchronously.
    runApp(const MbnmovieApp());
    unawaited(_showWindowsShell());
  } else if (isAndroidTv) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!kIsWeb) UpdatePresentation.start();
    runApp(const MbnmovieApp());
  } else {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    if (!kIsWeb) UpdatePresentation.start();
    runApp(const MbnmovieApp());
  }
  if (Platform.isWindows) {
    if (!kIsWeb) UpdatePresentation.start();
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (kIsWeb) return;
    AppLinks.registerThisApp(appId: 'MBNMovie', exeName: 'mbnmovie.exe');
    DownloadManager.instance.initialize().catchError((Object error) {
      DownloadManager.instance.error = 'راه‌اندازی دانلودها انجام نشد.';
    });
  });
}
