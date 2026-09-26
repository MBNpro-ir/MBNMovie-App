import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/desktop_window_frame.dart';
import 'core/theme.dart';
import 'core/platform_ui.dart';
import 'widgets/tv_navigation.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'screens/splash_screen.dart';
import 'screens/update_screen.dart';
import 'services/mbn_auth.dart';
import 'services/mbn_sync.dart';
import 'services/movie_api.dart';

class MbnmovieApp extends StatefulWidget {
  const MbnmovieApp({super.key});

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
  bool _checkingAccount = false;
  bool _terminating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _accountTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _checkAccount(),
    );
    _restoreSession();
  }

  @override
  void dispose() {
    _accountTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkAccount();
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
        await _forceLogout('نشست شما پایان یافته است؛ دوباره وارد شوید.');
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
    MbnSync.instance.clear();
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
      }
    }
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appMessengerKey,
      debugShowCheckedModeBanner: false,
      title: 'MBNMovie',
      theme: isAndroidTv
          ? MovieTheme.dark.copyWith(
              visualDensity: VisualDensity.standard,
              focusColor: MovieColors.cyan.withValues(alpha: .4),
              hoverColor: MovieColors.cyan.withValues(alpha: .15),
            )
          : MovieTheme.dark,
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
          child: TvNavigation(child: MandatoryUpdateGate(child: child!)),
        ),
      ),
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .985, end: 1).animate(animation),
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
                    await MbnSync.instance.pushAll();
                  } catch (_) {}
                  MbnSync.instance.clear();
                  await _auth.logout();
                  _loggedIn = false;
                  _refresh();
                },
              )
            : LoginScreen(
                key: const ValueKey('login'),
                onLogin: (identifier, password) async {
                  await _auth.login(identifier: identifier, password: password);
                  MbnSync.instance.configure(auth: _auth);
                  await MbnSync.instance.syncAll();
                  _loggedIn = true;
                  _refresh();
                },
              ),
      ),
    );
  }
}
