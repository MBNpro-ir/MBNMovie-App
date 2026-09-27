import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../core/platform_ui.dart';
import '../services/app_updater.dart';
import '../services/device_bridge.dart';

Future<String?> showInstallPermissionPrompt(
  BuildContext context,
) => showDialog<String>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('اجازهٔ نصب لازم است'),
    content: const Text(
      'برای نصب بروزرسانی، گزینهٔ «اجازه از این منبع» را برای MBNMovie فعال کن و به برنامه برگرد. فایل دانلودشده محفوظ است. می‌توانی دوباره اجازه بدهی یا از گیت‌هاب دستی دانلود کنی.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('بعداً'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, 'github'),
        child: const Text('دانلود از گیت‌هاب'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, 'retry'),
        child: const Text('درخواست دوباره'),
      ),
    ],
  ),
);

Future<void> _installUpdate(BuildContext context, AppUpdater updater) async {
  do {
    await updater.install();
    if (!context.mounted || !updater.installationPermissionRequired) return;
    final choice = await showInstallPermissionPrompt(context);
    if (!context.mounted) return;
    if (choice == 'retry') continue;
    if (choice == 'github') await _openRelease(context);
    return;
  } while (context.mounted);
}

Future<void> _openRelease(BuildContext context) async {
  try {
    if (await launchUrl(
      Uri.https('github.com', '/${AppUpdater.repository}/releases/latest'),
      mode: LaunchMode.externalApplication,
    )) {
      return;
    }
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'مرورگر باز نشد. آدرس: github.com/MBNpro-ir/MBNMovie-App/releases/latest',
        ),
      ),
    );
  }
}

class UpdatePresentation {
  static bool _dialog = false;
  static bool _started = false;
  static Timer? _periodicCheck;
  static void start() {
    if (_started) return;
    _started = true;
    AppUpdater.instance.addListener(_changed);
    DeviceBridge.installStatus.addListener(_installStatusChanged);
    unawaited(AppUpdater.instance.initialize());
    _periodicCheck ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => checkNow(),
    );
  }

  static void checkNow() => unawaited(AppUpdater.instance.check());

  static void _installStatusChanged() {
    AppUpdater.instance.handleNativeInstallStatus(
      DeviceBridge.installStatus.value,
    );
  }

  static void _changed() {
    final updater = AppUpdater.instance;
    final context = appNavigatorKey.currentContext;
    if (context == null || _dialog) return;
    if (updater.installedNotes != null) {
      final notes = updater.installedNotes!;
      updater.installedNotes = null;
      _dialog = true;
      unawaited(
        showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('🎉 به نسخهٔ ${updater.currentVersion} بروز شدی'),
            content: SingleChildScrollView(
              child: SelectableText(
                notes.isEmpty ? 'برنامه با موفقیت بروزرسانی شد.' : notes,
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('عالیه'),
              ),
            ],
          ),
        ).whenComplete(() {
          _dialog = false;
          _changed();
        }),
      );
    }
  }
}

class MandatoryUpdateGate extends StatefulWidget {
  const MandatoryUpdateGate({super.key, required this.child, this.updater});

  final Widget child;
  final AppUpdater? updater;

  @override
  State<MandatoryUpdateGate> createState() => _MandatoryUpdateGateState();
}

class _MandatoryUpdateGateState extends State<MandatoryUpdateGate> {
  AppUpdater get _updater => widget.updater ?? AppUpdater.instance;
  String? _attemptedVersion;
  bool _installing = false;

  void _scheduleAutomaticInstall(AppUpdater updater) {
    final version =
        updater.requiredRelease?.version.toString() ??
        updater.release?.version.toString();
    if (version == null ||
        !updater.canInstallRequiredRelease ||
        _installing ||
        updater.installationPermissionRequired ||
        _attemptedVersion == version) {
      return;
    }
    _attemptedVersion = version;
    _installing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await updater.install();
      if (mounted) setState(() => _installing = false);
    });
  }

  Future<void> _retryInstall() async {
    setState(() {
      _attemptedVersion = null;
      _installing = true;
    });
    await _updater.install();
    if (mounted) setState(() => _installing = false);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _updater,
    builder: (context, _) {
      final updater = _updater;
      final required =
          updater.requiredRelease != null ||
          (updater.release != null && updater.phase != UpdatePhase.idle);
      if (!required) return widget.child;
      if (updater.phase == UpdatePhase.ready) {
        _scheduleAutomaticInstall(updater);
      }
      return Stack(
        children: [
          FocusScope(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            child: ExcludeSemantics(
              child: IgnorePointer(
                key: const Key('mandatory-update-blocked-content'),
                child: widget.child,
              ),
            ),
          ),
          Positioned.fill(
            child: PopScope(
              canPop: false,
              child: Material(
                color: MovieColors.background.withValues(alpha: .98),
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: _mandatoryCard(context, updater),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );

  Widget _mandatoryCard(BuildContext context, AppUpdater updater) {
    final downloading = updater.phase == UpdatePhase.downloading;
    final checking = updater.phase == UpdatePhase.checking;
    final installing = updater.phase == UpdatePhase.installing || _installing;
    final needsPermission = updater.installationPermissionRequired;
    final hasFailure =
        updater.phase == UpdatePhase.failed || updater.error != null;
    final title = checking
        ? 'در حال بررسی دوبارهٔ به‌روزرسانی'
        : downloading
        ? 'به‌روزرسانی در حال دانلود است'
        : installing
        ? 'به‌روزرسانی در حال نصب است'
        : needsPermission
        ? 'اجازهٔ نصب Android لازم است'
        : hasFailure
        ? 'به‌روزرسانی کامل نشد'
        : 'در حال آماده‌سازی نصب';
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MovieColors.orange.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                downloading
                    ? Icons.downloading_rounded
                    : installing
                    ? Icons.install_desktop_rounded
                    : hasFailure
                    ? Icons.error_outline_rounded
                    : Icons.system_update_alt_rounded,
                size: 42,
                color: hasFailure
                    ? Theme.of(context).colorScheme.error
                    : MovieColors.orange,
              ),
            ),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              updater.requiredRelease == null && updater.release == null
                  ? 'پیش از ورود، آخرین نسخهٔ برنامه بررسی می‌شود.'
                  : 'نسخهٔ ${updater.requiredRelease?.version ?? updater.release!.version} برای ادامهٔ استفاده از برنامه لازم است. این صفحه پس از تکمیل به‌روزرسانی خودکار بسته می‌شود.',
              style: const TextStyle(color: MovieColors.muted),
            ),
            if (checking || downloading || installing) ...[
              const SizedBox(height: 22),
              LinearProgressIndicator(
                value: downloading ? updater.progress : null,
                minHeight: 9,
                borderRadius: BorderRadius.circular(9),
              ),
              const SizedBox(height: 9),
              Text(
                checking
                    ? 'در حال اتصال به انتشار رسمی…'
                    : downloading && updater.progress != null
                    ? '${(updater.progress! * 100).clamp(0, 100).round()}٪ دانلود شده'
                    : installing && Platform.isAndroid
                    ? 'Android در حال بررسی و نصب بسته است…'
                    : 'برنامه بسته و پس از نصب دوباره اجرا می‌شود…',
                textAlign: TextAlign.center,
                style: const TextStyle(color: MovieColors.muted),
              ),
            ],
            if (needsPermission) ...[
              const SizedBox(height: 16),
              const Text(
                'گزینهٔ «اجازه از این منبع» را فعال کن و به برنامه برگرد. بدون این اجازه Android نصب را آغاز نمی‌کند.',
              ),
            ],
            if (updater.error != null) ...[
              const SizedBox(height: 16),
              Text(
                updater.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (needsPermission || hasFailure) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _installing
                    ? null
                    : hasFailure && updater.phase == UpdatePhase.failed
                    ? updater.check
                    : _retryInstall,
                icon: Icon(
                  needsPermission
                      ? Icons.security_rounded
                      : Icons.refresh_rounded,
                ),
                label: Text(
                  needsPermission ? 'فعال‌کردن اجازه و ادامه' : 'تلاش دوباره',
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => _openRelease(context),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('دانلود دستی از گیت‌هاب'),
              ),
            ],
            const SizedBox(height: 14),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: MovieColors.cyan,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'فایل فقط پس از بررسی اندازه و SHA-256 نصب می‌شود.',
                    style: TextStyle(color: MovieColors.muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UpdateScreen extends StatelessWidget {
  const UpdateScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('به‌روزرسانی برنامه')),
    body: ListenableBuilder(
      listenable: AppUpdater.instance,
      builder: (context, _) {
        final updater = AppUpdater.instance;
        return LayoutBuilder(
          builder: (context, constraints) {
            final desktop = constraints.maxWidth >= 900;
            final padding = desktop ? 28.0 : 12.0;
            final status = _statusPanel(context, updater, desktop: desktop);
            final details = _detailsPanel(context, updater, desktop: desktop);
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 18, padding, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: desktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 350, child: status),
                            const SizedBox(width: 18),
                            Expanded(child: details),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            status,
                            const SizedBox(height: 12),
                            details,
                          ],
                        ),
                ),
              ),
            );
          },
        );
      },
    ),
  );

  Widget _statusPanel(
    BuildContext context,
    AppUpdater updater, {
    required bool desktop,
  }) {
    final phaseColor = _phaseColor(context, updater.phase);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(desktop ? 24 : 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                width: desktop ? 76 : 62,
                height: desktop ? 76 : 62,
                decoration: BoxDecoration(
                  color: phaseColor.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  _phaseIcon(updater.phase),
                  color: phaseColor,
                  size: desktop ? 40 : 34,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _phaseTitle(updater),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'نسخهٔ نصب‌شده: ${updater.currentVersion.isEmpty ? 'در حال تشخیص…' : updater.currentVersion}',
              style: const TextStyle(color: MovieColors.muted),
            ),
            if (updater.release != null) ...[
              const SizedBox(height: 4),
              Text(
                'آخرین نسخه: ${updater.release!.version}',
                style: const TextStyle(color: MovieColors.muted),
              ),
            ],
            if (_isBusy(updater.phase)) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(
                value: updater.phase == UpdatePhase.downloading
                    ? updater.progress
                    : null,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              if (updater.phase == UpdatePhase.downloading &&
                  updater.progress != null) ...[
                const SizedBox(height: 7),
                Text(
                  '${(updater.progress! * 100).clamp(0, 100).round()}٪ دریافت شده',
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: MovieColors.muted),
                ),
              ],
            ],
            if (updater.error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  updater.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailsPanel(
    BuildContext context,
    AppUpdater updater, {
    required bool desktop,
  }) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: EdgeInsets.all(desktop ? 24 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.new_releases_rounded, color: MovieColors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  updater.release == null
                      ? 'وضعیت به‌روزرسانی'
                      : 'تازه‌های نسخهٔ ${updater.release!.version}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          if (updater.release == null)
            const Text(
              'برنامه در هر اجرا آخرین انتشار رسمی را بررسی می‌کند. برای بررسی دستی از دکمهٔ زیر استفاده کن.',
              style: TextStyle(color: MovieColors.muted),
            )
          else
            SelectableText(
              updater.release!.notes.trim().isEmpty
                  ? 'برای این نسخه توضیحی ثبت نشده است.'
                  : updater.release!.notes,
            ),
          const SizedBox(height: 24),
          if (updater.phase == UpdatePhase.ready)
            FilledButton.icon(
              onPressed: () => _confirmInstall(context, updater),
              icon: Icon(
                Theme.of(context).platform == TargetPlatform.android
                    ? Icons.install_mobile_rounded
                    : Icons.install_desktop_rounded,
              ),
              label: const Text('نصب به‌روزرسانی'),
            ),
          if (updater.phase == UpdatePhase.ready) const SizedBox(height: 8),
          if (desktop)
            Row(
              children: [
                Expanded(child: _githubButton(context)),
                const SizedBox(width: 8),
                Expanded(child: _retryButton(updater)),
              ],
            )
          else ...[
            _retryButton(updater),
            const SizedBox(height: 8),
            _githubButton(context),
          ],
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 19,
                color: MovieColors.cyan,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Theme.of(context).platform == TargetPlatform.android
                      ? 'پس از دانلود و بررسی صحت فایل، اجازهٔ نصب Android نمایش داده می‌شود.'
                      : 'بسته پس از دانلود و بررسی صحت فایل نصب می‌شود؛ برنامه دوباره اجرا خواهد شد.',
                  style: const TextStyle(
                    color: MovieColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _retryButton(AppUpdater updater) => OutlinedButton.icon(
    onPressed: _isBusy(updater.phase) ? null : updater.check,
    icon: const Icon(Icons.refresh_rounded),
    label: const Text('بررسی دوباره'),
  );

  Widget _githubButton(BuildContext context) => TextButton.icon(
    onPressed: () => _openRelease(context),
    icon: const Icon(Icons.open_in_new_rounded),
    label: const Text('دانلود دستی از گیت‌هاب'),
  );

  Future<void> _confirmInstall(BuildContext context, AppUpdater updater) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('نصب به‌روزرسانی؟'),
        content: const Text(
          'در Windows برنامه بسته و پس از به‌روزرسانی دوباره باز می‌شود. دانلودهای جاری را ابتدا متوقف کن. در Android تأیید نصب سیستم نمایش داده می‌شود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('به‌روزرسانی کن'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) {
      await _installUpdate(context, updater);
    }
  }

  bool _isBusy(UpdatePhase phase) => const [
    UpdatePhase.checking,
    UpdatePhase.downloading,
    UpdatePhase.installing,
  ].contains(phase);

  String _phaseTitle(AppUpdater updater) => switch (updater.phase) {
    UpdatePhase.idle => 'برنامه به‌روز است',
    UpdatePhase.checking => 'در حال بررسی نسخهٔ جدید',
    UpdatePhase.downloading => 'در حال دانلود به‌روزرسانی',
    UpdatePhase.ready => 'به‌روزرسانی آمادهٔ نصب است',
    UpdatePhase.installing => 'در حال آماده‌سازی نصب',
    UpdatePhase.failed => 'بررسی به‌روزرسانی ناموفق بود',
  };

  IconData _phaseIcon(UpdatePhase phase) => switch (phase) {
    UpdatePhase.idle => Icons.verified_rounded,
    UpdatePhase.checking => Icons.manage_search_rounded,
    UpdatePhase.downloading => Icons.downloading_rounded,
    UpdatePhase.ready => Icons.system_update_alt_rounded,
    UpdatePhase.installing => Icons.install_desktop_rounded,
    UpdatePhase.failed => Icons.cloud_off_rounded,
  };

  Color _phaseColor(BuildContext context, UpdatePhase phase) => switch (phase) {
    UpdatePhase.idle => MovieColors.cyan,
    UpdatePhase.ready => Colors.greenAccent,
    UpdatePhase.failed => Theme.of(context).colorScheme.error,
    _ => MovieColors.orange,
  };
}
