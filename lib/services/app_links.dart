import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'device_bridge.dart';

/// The sibling app this build can hand off to.
class SiblingApp {
  const SiblingApp({
    required this.id,
    required this.name,
    required this.tagline,
    required this.androidPackage,
    required this.windowsExe,
    required this.githubReleasesUrl,
  });

  final String id;
  final String name;
  final String tagline;
  final String androidPackage;
  final String windowsExe;
  final String githubReleasesUrl;
}

/// MBNime, shown from MBNMovie.
const siblingAnime = SiblingApp(
  id: 'MBNime',
  name: 'MBNime',
  tagline:
      'اپ MBNime برای تماشای انیمه‌ها (دوبله و زیرنویس فارسی) روی این دستگاه نصب نیست. از صفحه انتشار گیت‌هاب دانلود و نصب کن.',
  androidPackage: 'com.mbn.ime',
  windowsExe: 'mbnime.exe',
  githubReleasesUrl: 'https://github.com/MBNpro-ir/MBNime-App/releases/latest',
);

/// Cross-app handoff between the portable/desktop and Android builds.
/// On Windows every launch records its own install folder in
/// HKCU\Software\MBN\Apps\<id> (via reg.exe, no extra dependency) so the
/// sibling build can be found wherever the user extracted it.
abstract final class AppLinks {
  static String registryKey(String appId) => r'HKCU\Software\MBN\Apps\' + appId;

  /// Parses `reg query` output for a REG_SZ value.
  @visibleForTesting
  static String? parseRegQueryValue(String output, String valueName) {
    for (final line in output.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 3 &&
          parts[0].toLowerCase() == valueName.toLowerCase() &&
          parts[1].toUpperCase() == 'REG_SZ') {
        return parts.sublist(2).join(' ').trim();
      }
    }
    return null;
  }

  /// Records this build's location for the sibling app. Best effort.
  static Future<void> registerThisApp({
    required String appId,
    required String exeName,
  }) async {
    if (!Platform.isWindows) return;
    try {
      final dir = p.dirname(Platform.resolvedExecutable);
      await Process.run('reg', [
        'add',
        registryKey(appId),
        '/v',
        'InstallDir',
        '/t',
        'REG_SZ',
        '/d',
        dir,
        '/f',
      ]);
      await Process.run('reg', [
        'add',
        registryKey(appId),
        '/v',
        'Exe',
        '/t',
        'REG_SZ',
        '/d',
        exeName,
        '/f',
      ]);
    } catch (_) {}
  }

  /// Resolves the sibling executable recorded in the registry, if any.
  static Future<String?> findSiblingExe(SiblingApp sibling) async {
    if (!Platform.isWindows) return null;
    try {
      final result = await Process.run('reg', [
        'query',
        registryKey(sibling.id),
        '/v',
        'InstallDir',
      ]);
      if (result.exitCode != 0) return null;
      final dir = parseRegQueryValue(result.stdout.toString(), 'InstallDir');
      if (dir == null || dir.isEmpty) return null;
      final exe = File(p.join(dir, sibling.windowsExe));
      if (await exe.exists()) return exe.path;
    } catch (_) {}
    return null;
  }

  /// Opens the sibling app and closes this one; otherwise shows the promo
  /// dialog with the GitHub download link.
  static Future<void> openSibling(
    BuildContext context,
    SiblingApp sibling,
  ) async {
    if (Platform.isAndroid) {
      try {
        if (await DeviceBridge.isAppInstalled(sibling.androidPackage)) {
          await DeviceBridge.openApp(sibling.androidPackage);
          await Future<void>.delayed(const Duration(milliseconds: 400));
          exit(0);
        }
      } catch (_) {}
      if (context.mounted) await showSiblingPromo(context, sibling);
      return;
    }
    if (Platform.isWindows) {
      final exe = await findSiblingExe(sibling);
      if (exe != null) {
        try {
          await Process.start(exe, const [], mode: ProcessStartMode.detached);
          exit(0);
        } catch (_) {}
      }
      if (context.mounted) await showSiblingPromo(context, sibling);
      return;
    }
    if (context.mounted) await showSiblingPromo(context, sibling);
  }

  static Future<void> showSiblingPromo(
    BuildContext context,
    SiblingApp sibling,
  ) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(sibling.name),
      content: Text(sibling.tagline),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('بستن'),
        ),
        FilledButton(
          onPressed: () {
            launchUrl(
              Uri.parse(sibling.githubReleasesUrl),
              mode: LaunchMode.externalApplication,
            );
          },
          child: const Text('دانلود از گیت‌هاب'),
        ),
      ],
    ),
  );
}
