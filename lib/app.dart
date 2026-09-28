import 'dart:async';

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
import 'services/auth_handoff.dart';
import 'services/accessibility_service.dart';
import 'services/app_links.dart';
import 'services/app_updater.dart';
import 'services/cross_app_auth.dart';

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
  Timer? _syncTimer;
  Timer? _handoffTimer;
  bool _handoffBusy = false;
  bool _siblingAvailable = false;
  bool _checkingAccount = false;
  bool _terminating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(TitleLanguage.initialize());
    _accountTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _checkAccount(),
    );
    _syncTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(MbnSync.instance.syncAll()),
    );
    _handoffTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_checkHandoff()),
    );
    unawaited(_checkSibling());
    _restoreSession();
  }

  @override
  void dispose() {
    _accountTimer?.cancel();
    _syncTimer?.cancel();
    _handoffTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAccount();
      UpdatePresentation.checkNow();
      unawaited(MbnSync.instance.syncAll());
      unawaited(_checkSibling());
      unawaited(_checkHandoff());
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

  Future<void> _checkSibling() async {
    final available = await AppLinks.isSiblingAvailable(siblingAnime);
    if (mounted && _siblingAvailable != available) {
      setState(() => _siblingAvailable = available);
    }
  }

  Future<void> _beginHandoff() async {
    final token = await CrossAppAuth.readSiblingToken(siblingId: 'MBNime');
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
      await _auth.loginWithToken(token);
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

  Future<void> _checkHandoff() async {
    if (_handoffBusy ||
        _restoring ||
        !mounted ||
        AppUpdater.instance.startupCheckPending ||
        AppUpdater.instance.requiredRelease != null) {
      return;
    }
    _handoffBusy = true;
    try {
      final message = await AppLinks.takeHandoff('MBNMovie');
      if (message == null) return;
      final parts = message.split(':');
      if (parts.length != 2 || parts[1].length < 20) return;
      if (parts[0] == 'request') {
        await _respondHandoff(parts[1]);
      } else if (parts[0] == 'return') {
        await _offerHandoff(parts[1]);
      }
    } finally {
      _handoffBusy = false;
    }
  }

  Future<void> _respondHandoff(String id) async {
    if (_loggedIn && _auth.token != null && _auth.profile != null) {
      final identifier = _auth.profile!.email.isNotEmpty
          ? _auth.profile!.email
          : _auth.profile!.username;
      final approved =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('ورود مشترک به MBNime'),
              content: Text(
                'حساب $identifier در MBNMovie فعال است. اجازه می‌دهی همین حساب در MBNime پیشنهاد شود؟',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('خیر'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('بله، پیشنهاد بده'),
                ),
              ],
            ),
          ) ??
          false;
      try {
        if (approved) {
          await AuthHandoff.approve(post: _auth.postJson, id: id);
        } else {
          await AuthHandoff.deny(post: _auth.postJson, id: id);
        }
      } catch (_) {}
    }
    await AppLinks.launchHandoff(siblingAnime, 'return:$id');
  }

  Future<void> _offerHandoff(String id) async {
    try {
      final status = await AuthHandoff.status(post: _auth.postJson, id: id);
      if (status == null || status['state'] != 'approved') {
        if (mounted) {
          appMessengerKey.currentState?.showSnackBar(
            const SnackBar(
              content: Text(
                'حساب فعالی در برنامهٔ دیگر تأیید نشد؛ می‌توانی دستی وارد شوی.',
              ),
            ),
          );
        }
        return;
      }
      final identifier = status['identifier']?.toString() ?? '';
      if (!mounted) return;
      final useIt =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              title: const Text('استفاده از حساب MBNime'),
              content: Text(
                'در MBNime با $identifier وارد شده‌ای. می‌خواهی همین حساب در MBNMovie استفاده شود؟',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('ورود با حساب دیگر'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('استفاده از همین حساب'),
                ),
              ],
            ),
          ) ??
          false;
      if (!useIt) return;
      final data = await AuthHandoff.consume(
        post: _auth.postJson,
        id: id,
        targetApp: 'movie',
      );
      if (data == null) return;
      await _auth.loginWithHandoff(data, identifier: identifier);
      await _bindDelfanSession();
      if (_auth.profile != null && _auth.profile!.id > 0) {
        await MbnSync.instance.bindAccount(_auth.profile!.id);
      }
      MbnSync.instance.configure(auth: _auth);
      await MbnSync.instance.syncAll();
      if (mounted) setState(() => _loggedIn = true);
    } catch (_) {
      if (mounted) {
        appMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('ورود مشترک انجام نشد؛ دوباره تلاش کن.'),
          ),
        );
      }
    } finally {
      await AuthHandoff.clear(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AccessibilityService.instance,
      builder: (context, _) {
        final access = AccessibilityService.instance;
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
              : MovieTheme.dark.copyWith(
                  visualDensity: access.visualDensity,
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
                  await _auth.loginWithHandoff(data, identifier: identifier);
                  await _bindDelfanSession();
                  MbnSync.instance.configure(auth: _auth);
                  if (_auth.profile != null && _auth.profile!.id > 0) {
                    await MbnSync.instance.bindAccount(_auth.profile!.id);
                  }
                  await MbnSync.instance.syncAll();
                  if (mounted) setState(() => _loggedIn = true);
                },
                onUseOtherApp: _siblingAvailable ? _beginHandoff : null,
                onLogin: (identifier, password) async {
                  await _auth.login(identifier: identifier, password: password);
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

  static EdgeInsets _scaleInsets(EdgeInsets insets, double scale) {
    if (scale <= 0) return insets;
    return EdgeInsets.fromLTRB(
      insets.left / scale,
      insets.top / scale,
      insets.right / scale,
      insets.bottom / scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AccessibilityService.instance,
      builder: (context, _) {
        final access = AccessibilityService.instance;
        final uiScale = access.uiScale;
        final textScale = access.textScale;

        return LayoutBuilder(
          builder: (context, constraints) {
            final media = MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              boldText: access.boldText,
              disableAnimations: access.reduceMotion,
            );

            if ((uiScale - 1.0).abs() < 0.01) {
              return MediaQuery(data: media, child: child);
            }

            final scaledWidth = constraints.maxWidth / uiScale;
            final scaledHeight = constraints.maxHeight / uiScale;

            return Transform.scale(
              scale: uiScale,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: scaledWidth,
                height: scaledHeight,
                child: MediaQuery(
                  data: media.copyWith(
                    size: Size(scaledWidth, scaledHeight),
                    padding: _scaleInsets(media.padding, uiScale),
                    viewPadding: _scaleInsets(media.viewPadding, uiScale),
                    viewInsets: _scaleInsets(media.viewInsets, uiScale),
                  ),
                  child: child,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

