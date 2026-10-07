import 'package:flutter/services.dart';
import 'services/device_performance.dart';
import 'dart:async';
import 'services/session_watch.dart';
import 'services/browser_features.dart';
import 'widgets/session_devices_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/desktop_window_frame.dart';
import 'core/theme.dart';
import 'core/title_language.dart';
import 'core/platform_ui.dart';
import 'widgets/tv_navigation.dart';
import 'widgets/server_status_gate.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';
import 'screens/update_screen.dart';
import 'services/mbn_auth.dart';
import 'services/mbn_sync.dart';
import 'services/movie_api.dart';
import 'services/accessibility_service.dart';
import 'services/cross_app_auth.dart';

class MbnmovieApp extends StatefulWidget {
  const MbnmovieApp({super.key, this.sharedTokenReader});

  final Future<String?> Function()? sharedTokenReader;

  @override
  State<MbnmovieApp> createState() => _MbnmovieAppState();
}

class _MbnmovieAppState extends State<MbnmovieApp> with WidgetsBindingObserver {
  static const _debugIdentifier = String.fromEnvironment(
    'MBN_DEBUG_IDENTIFIER',
  );
  static const _debugPassword = String.fromEnvironment('MBN_DEBUG_PASSWORD');
  final MovieApi _api = MovieApi();
  final MbnAuth _auth = MbnAuth();
  bool _restoring = true;
  bool _loggedIn = false;
  Timer? _accountTimer;
  Timer? _syncTimer;
  bool _checkingAccount = false;
  bool _terminating = false;
  late final SessionWatch _sessionWatch = SessionWatch(_forceLogout);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api.catalogRequest = (path, query) => _auth.getJson(path, query: query);
    unawaited(TitleLanguage.initialize());
    _accountTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      unawaited(_checkAccount());
    });
    _syncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(MbnSync.instance.syncAll()),
    );
    _restoreSession();
  }

  @override
  void dispose() {
    _sessionWatch.dispose();
    _accountTimer?.cancel();
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccount();
      UpdatePresentation.checkNow();
      unawaited(MbnSync.instance.syncAll());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(MbnSync.instance.flushPending());
    }
  }

  Future<void> _checkAccount() async {
    if ((_auth.token == null && !_loggedIn) ||
        _checkingAccount ||
        _terminating) {
      return;
    }
    _checkingAccount = true;
    try {
      final message = await _auth.accountRestriction();
      if (message != null) {
        await _forceLogout(message);
      } else if (!_loggedIn && await _auth.restore()) {
        if (mounted) setState(() => _loggedIn = true);
      }
    } on MbnAuthException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _forceLogout(
          error.message.isNotEmpty
              ? error.message
              : 'نشست شما پایان یافته است؛ دوباره وارد شوید.',
        );
      }
    } catch (_) {
      // A network failure must not sign out the user.
    } finally {
      _checkingAccount = false;
    }
  }

  Future<void> _forceLogout(String message) async {
    if (_terminating || !mounted) return;
    _terminating = true;
    if (kIsWeb) BrowserFeatures.stop();
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    MbnSync.instance.clear();
    _api.clearDelfanSession();
    await _auth.logout();
    if (!mounted) return;
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    setState(() => _loggedIn = false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _showLogoutDialog(message),
    );
  }

  Future<void> _showLogoutDialog(String message) async {
    final dialogContext = appNavigatorKey.currentContext;
    if (!mounted || dialogContext == null) return;
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('خروج از حساب'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('رفتن به ورود'),
          ),
        ],
      ),
    );
    _terminating = false;
  }

  Future<void> _restoreSession() async {
    bool ok = false;
    try {
      await Future.wait([
        () async {
          ok = await _auth.restore();
          if (!ok &&
              _auth.forcedLogoutMessage == null &&
              kDebugMode &&
              _debugIdentifier.isNotEmpty &&
              _debugPassword.isNotEmpty) {
            await _auth.login(
              identifier: _debugIdentifier,
              password: _debugPassword,
            );
            ok = true;
          }
          if (ok) {
            await _bindDelfanSession();
            if (_auth.profile != null && _auth.profile!.id > 0) {
              await MbnSync.instance.bindAccount(_auth.profile!.id);
            }
            MbnSync.instance.configure(auth: _auth);
            await MbnSync.instance.syncAll();
          }
        }(),
        Future<void>.delayed(const Duration(milliseconds: 1450)),
      ]);
    } catch (_) {
      // restore() itself never throws; this guard only ensures a storage
      // failure can never brick the app on the splash screen.
    }
    if (mounted) {
      setState(() {
        _loggedIn = ok && _auth.profile != null;
        _restoring = false;
      });
      final message = _auth.forcedLogoutMessage;
      if (message != null) {
        _terminating = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _showLogoutDialog(message),
        );
      } else if (_loggedIn) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = appNavigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            unawaited(MbnSync.instance.checkOtherAppSettingsPrompt(ctx));
          }
        });
      }
    }
  }

  void _refresh() => setState(() {});

  Future<void> _bindDelfanSession() async {
    _api.clearDelfanSession();
    if (_auth.profile?.delfanVerified != true) return;
    try {
      final data = await _auth.getJson('/api/me/delfan/session');
      _api.bindDelfanSession(
        mobile: data['mobile']?.toString() ?? '',
        password: data['password']?.toString() ?? '',
      );
    } catch (_) {
      // Catalog can still use its guest/index fallback when the link is down.
    }
  }

  Future<bool> _loginWithCapacity(
    Future<dynamic> Function() action,
    String identifier,
  ) async {
    try {
      await action();
      return true;
    } on MbnAuthException catch (error) {
      if (error.details?['code'] != 'session_limit') rethrow;
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) rethrow;
      final result = await showSessionDevicesDialog(
        ctx,
        error.details!,
        _auth.postJson,
      );
      if (result == null) return false;
      await _auth.loginWithHandoff(result, identifier: identifier);
      return true;
    } finally {
    }
  }

  Future<void> _beginHandoff() async {
    final token =
        await (widget.sharedTokenReader?.call() ??
            CrossAppAuth.readSiblingToken(siblingId: 'MBNime'));
    if (!mounted || _terminating) return;
    if (token == null || token.isEmpty) {
      if (mounted) {
        appMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'حساب فعالی در برنامه MBNime یافت نشد. ابتدا در MBNime وارد شوید.',
            ),
          ),
        );
      }
      return;
    }
    try {
      if (!await _loginWithCapacity(
        () => _auth.loginWithToken(token),
        'کاربر',
      )) {
        return;
      }
      await _bindDelfanSession();
      MbnSync.instance.configure(auth: _auth);
      if (_auth.profile != null && _auth.profile!.id > 0) {
        await MbnSync.instance.bindAccount(_auth.profile!.id);
      }
      await MbnSync.instance.syncAll();
      if (mounted) {
        setState(() => _loggedIn = true);
        final displayName = _auth.profile?.name.isNotEmpty == true
            ? _auth.profile!.name
            : (_auth.profile?.email.isNotEmpty == true
                  ? _auth.profile!.email
                  : _auth.profile?.username ?? '');
        appMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              displayName.isNotEmpty
                  ? 'ورود با حساب MBNime ($displayName)'
                  : 'ورود با حساب MBNime با موفقیت انجام شد.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        appMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'ورود با حساب MBNime ناموفق بود؛ لطفاً دوباره تلاش کنید.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _sessionWatch.track(_auth.token, _auth.baseUrl);
    return ListenableBuilder(
      listenable: AccessibilityService.instance,
      builder: (context, _) {
        final access = AccessibilityService.instance;
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          scaffoldMessengerKey: appMessengerKey,
          debugShowCheckedModeBanner: false,
          title: 'MBNMovie',
          theme: MovieTheme.buildTheme(
            highContrast: access.highContrast,
            visualDensity: isAndroidTv
                ? VisualDensity.standard
                : access.visualDensity,
            reduceMotion: access.reduceMotion,
            boldText: access.boldText,
            focusColor: isAndroidTv
                ? MovieColors.cyan.withValues(alpha: .4)
                : null,
            hoverColor: isAndroidTv
                ? MovieColors.cyan.withValues(alpha: .15)
                : null,
          ),
          locale: const Locale('fa', 'IR'),
          // Actually localize framework-provided strings (back-button tooltips,
          // selection menus, accessibility labels): a bare `locale` + forced
          // RTL only affects app-authored text/layout, leaving Flutter's own
          // controls in English without delegates + supportedLocales.
          supportedLocales: const [Locale('fa', 'IR'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => DesktopWindowFrame(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: MandatoryUpdateGate(
                child: TvNavigation(
                  child: ServerStatusGate(
                    child: AccessibilityAppWrapper(child: child!),
                  ),
                ),
              ),
            ),
          ),
          home: AnimatedSwitcher(
            duration: access.reduceMotion
                ? Duration.zero
                : Duration(
                    milliseconds: DevicePerformance.lightweight ? 180 : 650,
                  ),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) =>
                access.reduceMotion || DevicePerformance.lightweight
                ? child
                : FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: .985,
                        end: 1,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
            child: _restoring
                ? const SplashScreen(key: ValueKey('splash'))
                : _loggedIn
                ? MainShell(
                    key: const ValueKey('main'),
                    email: (_auth.profile?.email.isNotEmpty ?? false)
                        ? _auth.profile!.email
                        : (_auth.profile?.username.isNotEmpty ?? false)
                        ? _auth.profile!.username
                        : 'کاربر',
                    auth: _auth,
                    api: _api,
                    onLogout: () async {
                      try {
                        await MbnSync.instance.flushPending();
                      } catch (_) {}
                      MbnSync.instance.clear();
                      _api.clearDelfanSession();
                      await _auth.logout();
                      _loggedIn = false;
                      _refresh();
                    },
                  )
                : LoginScreen(
                    key: const ValueKey('login'),
                    auth: _auth,
                    onAuthenticated: (data, identifier) async {
                      await _auth.loginWithHandoff(
                        data,
                        identifier: identifier,
                      );
                      await _bindDelfanSession();
                      MbnSync.instance.configure(auth: _auth);
                      if (_auth.profile != null && _auth.profile!.id > 0) {
                        await MbnSync.instance.bindAccount(_auth.profile!.id);
                      }
                      await MbnSync.instance.syncAll();
                      if (mounted) setState(() => _loggedIn = true);
                    },
                    onUseOtherApp: _beginHandoff,
                    onLogin: (identifier, password) async {
                      if (!await _loginWithCapacity(
                        () => _auth.login(
                          identifier: identifier,
                          password: password,
                        ),
                        identifier,
                      )) {
                        return;
                      }
                      TextInput.finishAutofillContext(shouldSave: true);
                      await _bindDelfanSession();
                      MbnSync.instance.configure(auth: _auth);
                      if (_auth.profile != null && _auth.profile!.id > 0) {
                        await MbnSync.instance.bindAccount(_auth.profile!.id);
                      }
                      await MbnSync.instance.syncAll();
                      _loggedIn = true;
                      _refresh();
                    },
                  ),
          ),
        );
      },
    );
  }
}

class AccessibilityAppWrapper extends StatelessWidget {
  const AccessibilityAppWrapper({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AccessibilityService.instance,
      builder: (context, _) {
        final access = AccessibilityService.instance;
        final uiScale = access.uiScale;
        final textScale = access.textScale;

        final rawMedia = MediaQuery.of(context);
        final baseMedia = rawMedia.copyWith(
          textScaler: TextScaler.linear(textScale),
          boldText: access.boldText,
          disableAnimations: access.reduceMotion,
        );

        if (rawMedia.size.isEmpty ||
            rawMedia.size.width <= 0 ||
            rawMedia.size.height <= 0 ||
            (uiScale - 1.0).abs() < 0.005) {
          return MediaQuery(data: baseMedia, child: child);
        }

        final targetWidth = rawMedia.size.width / uiScale;
        final targetHeight = rawMedia.size.height / uiScale;

        final scaledMedia = baseMedia.copyWith(
          size: Size(targetWidth, targetHeight),
          padding: EdgeInsets.fromLTRB(
            rawMedia.padding.left / uiScale,
            rawMedia.padding.top / uiScale,
            rawMedia.padding.right / uiScale,
            rawMedia.padding.bottom / uiScale,
          ),
          viewPadding: EdgeInsets.fromLTRB(
            rawMedia.viewPadding.left / uiScale,
            rawMedia.viewPadding.top / uiScale,
            rawMedia.viewPadding.right / uiScale,
            rawMedia.viewPadding.bottom / uiScale,
          ),
          viewInsets: EdgeInsets.fromLTRB(
            rawMedia.viewInsets.left / uiScale,
            rawMedia.viewInsets.top / uiScale,
            rawMedia.viewInsets.right / uiScale,
            rawMedia.viewInsets.bottom / uiScale,
          ),
        );

        return SizedBox(
          width: rawMedia.size.width,
          height: rawMedia.size.height,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: targetWidth,
              height: targetHeight,
              child: MediaQuery(data: scaledMedia, child: child),
            ),
          ),
        );
      },
    );
  }
}
