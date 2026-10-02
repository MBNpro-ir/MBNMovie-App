import '../services/device_performance.dart';
import 'app_platform.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import '../services/accessibility_service.dart';

/// Shared navigator/messenger keys (single source used by the app shell and
/// the mandatory-update gate).
final appNavigatorKey = GlobalKey<NavigatorState>();
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// True on desktop window builds (custom title bar, no bottom nav).
bool get isDesktopWindow => Platform.isWindows;
bool isAndroidTv = false;
bool get isLargeScreenDevice => isDesktopWindow || isAndroidTv;

/// Bottom sheets remain full-width on phones, while TV/desktop use a readable
/// dialog-like width instead of stretching controls across the whole display.
double panelWidth(BuildContext context, {double large = 760}) =>
    isLargeScreenDevice || (kIsWeb && MediaQuery.sizeOf(context).width >= 600)
    ? math.min(large, MediaQuery.sizeOf(context).width - 32)
    : MediaQuery.sizeOf(context).width;

Future<void> initializeDeviceLayout() async {
  if (!Platform.isAndroid) return;
  try {
    isAndroidTv =
        await const MethodChannel(
          'com.mbn.movie/device',
        ).invokeMethod<bool>('isTelevision') ??
        false;
  } on MissingPluginException {
    // Hot restart can still be attached to the old native Android binary.
    // Keep that session usable until a full run installs the new bridge.
    isAndroidTv = false;
  }
}

/// When true (desktop), the custom window title bar is hidden — used for
/// distraction-free fullscreen video. Only the player toggles this.
final hideWindowChrome = ValueNotifier<bool>(false);

/// Bottom breathing room: lists reserve space for the mobile nav bar,
/// which is hidden on desktop.
double get bottomListGap => isLargeScreenDevice ? 28 : 110;

/// Shared route for inner pages. Android deliberately uses a Material route so
/// its predictive-back transition can follow the system edge-swipe in real
/// time; desktop keeps the custom slide/fade transition.
PageRoute<void> slideUpRoute(Widget page, {int durationMs = 380}) {
  if (DevicePerformance.lightweight) {
    durationMs = DevicePerformance.routeDuration.inMilliseconds;
  }
  if (AccessibilityService.instance.reduceMotion) {
    return PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => page,
    );
  }
  if (Platform.isAndroid) {
    return _MbnmovieAndroidPageRoute(page: page, durationMs: durationMs);
  }
  return PageRouteBuilder<void>(
    transitionDuration: Duration(milliseconds: durationMs),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _MbnmovieAndroidPageRoute extends MaterialPageRoute<void> {
  _MbnmovieAndroidPageRoute({required Widget page, required this.durationMs})
    : super(builder: (_) => page);

  final int durationMs;

  @override
  Duration get transitionDuration => Duration(milliseconds: durationMs);

  @override
  Duration get reverseTransitionDuration => DevicePerformance.lightweight
      ? const Duration(milliseconds: 180)
      : const Duration(milliseconds: 320);
}

/// Desktop-only large modal host: centered and only closable via in-page
/// navigation (outside taps do nothing).
Future<T?> showDesktopPopup<T>(BuildContext context, Widget child) {
  final reduceMotion = AccessibilityService.instance.reduceMotion;
  final size = MediaQuery.sizeOf(context);
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: .72),
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 260),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: MovieColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 1200,
            maxHeight: size.height * .96,
            minWidth: math.min(720.0, size.width * .9),
          ),
          child: SizedBox(
            width: math.min(1200.0, size.width * .96),
            height: size.height * .96,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: ScaffoldMessenger(child: child),
            ),
          ),
        ),
      ),
      transitionsBuilder: (_, animation, _, routeChild) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .965, end: 1).animate(curved),
            child: routeChild,
          ),
        );
      },
    ),
  );
}

/// A center-arc flight feels natural when a poster moves into the portrait
/// summary slot and follows the same path in reverse when the page closes.
RectTween smoothHeroRectTween(Rect? begin, Rect? end) =>
    MaterialRectCenterArcTween(begin: begin, end: end);

/// Always paints the detail-side artwork during a Hero flight. The catalog
/// card also contains labels and badges; letting Flutter switch between those
/// two different trees mid-flight causes a visible image/text flash.
/// The flight itself is decorative: it stays out of the accessibility tree so
/// rapid reparenting does not spam engine AX updates.
Widget portraitHeroFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final detailHero =
      (direction == HeroFlightDirection.push
              ? toHeroContext.widget
              : fromHeroContext.widget)
          as Hero;
  return Material(
    type: MaterialType.transparency,
    child: ExcludeSemantics(child: detailHero.child),
  );
}
