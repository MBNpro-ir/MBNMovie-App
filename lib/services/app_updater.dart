import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/release_update.dart';
import 'device_bridge.dart';
import 'download_manager.dart';

enum UpdatePhase { idle, checking, downloading, ready, installing, failed }

class AppUpdater extends ChangeNotifier {
  AppUpdater._();
  @visibleForTesting
  AppUpdater.testing({
    required this.currentVersion,
    required Directory cacheDirectory,
    required Uri Function(Uri) route,
    required String platform,
    Future<bool> Function()? requestInstallPermission,
    Future<String> Function(String)? installApk,
  }) : _testCache = cacheDirectory,
       _testRoute = route,
       _testPlatform = platform,
       _testRequestInstallPermission = requestInstallPermission,
       _testInstallApk = installApk;
  Future<bool> Function()? _testRequestInstallPermission;
  Future<String> Function(String)? _testInstallApk;
  Directory? _testCache;
  Uri Function(Uri)? _testRoute;
  String? _testPlatform;
  static final instance = AppUpdater._();
  static const repository = 'MBNpro-ir/MBNMovie-App';
  UpdatePhase phase = UpdatePhase.idle;
  ReleaseUpdate? release;
  ReleaseUpdate? requiredRelease;
  String currentVersion = '';
  String? error, installedNotes;
  double? progress;
  bool _busy = false;
  bool startupCheckPending = false;
  bool installationPermissionRequired = false;
  File? _package;

  bool get canInstallRequiredRelease =>
      release != null &&
      (requiredRelease == null ||
          (release!.version.compareTo(requiredRelease!.version) >= 0 &&
              release!.sha256 == requiredRelease!.sha256));

  Future<Directory> _cache() async {
    if (_testCache != null) return _testCache!.create(recursive: true);
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'updates')).create(recursive: true);
  }

  Future<void> initialize() async {
    startupCheckPending = true;
    phase = UpdatePhase.checking;
    notifyListeners();
    try {
      if (currentVersion.isEmpty) {
        currentVersion = (await PackageInfo.fromPlatform()).version;
      }
      final prefs = await SharedPreferences.getInstance();
      final required = prefs.getString('update_required');
      if (required != null) {
        try {
          final stored = ReleaseUpdate.fromStored(
            jsonDecode(required) as Map<String, dynamic>,
            repository: repository,
            platform: _testPlatform ?? await DeviceBridge.updatePlatform(),
          );
          final current = AppVersion.parse(currentVersion);
          if (stored == null ||
              current == null ||
              stored.version.compareTo(current) <= 0) {
            await prefs.remove('update_required');
          } else {
            requiredRelease = stored;
            notifyListeners();
          }
        } catch (_) {
          await prefs.remove('update_required');
        }
      }
      final pending = prefs.getString('update_pending');
      if (pending != null) {
        try {
          final data = jsonDecode(pending) as Map<String, dynamic>;
          final previousTarget = AppVersion.parse(data['version'] as String);
          final current = AppVersion.parse(currentVersion);
          if (current != null &&
              previousTarget != null &&
              current.compareTo(previousTarget) >= 0) {
            installedNotes = data['notes'] as String? ?? '';
            await prefs.remove('update_pending');
          } else if (current != null && previousTarget != null) {
            final cachedRelease = ReleaseUpdate.fromStored(
              data,
              repository: repository,
              platform: _testPlatform ?? await DeviceBridge.updatePlatform(),
            );
            if (cachedRelease != null) {
              final cache = await _cache();
              final file = File(
                p.join(
                  cache.path,
                  '${cachedRelease.sha256}-${cachedRelease.filename}',
                ),
              );
              if (await _validPackage(file, cachedRelease)) {
                release = cachedRelease;
                _package = file;
                requiredRelease ??= cachedRelease;
                notifyListeners();
              }
            }
          }
        } catch (_) {
          await prefs.remove('update_pending');
        }
      }
      await check();
    } catch (_) {
      error = 'بررسی بروزرسانی انجام نشد؛ اتصال اینترنت را بررسی کن.';
      phase = UpdatePhase.failed;
      notifyListeners();
    } finally {
      startupCheckPending = false;
      notifyListeners();
    }
  }

  Future<void> check() async {
    if (_busy) return;
    _busy = true;
    error = null;
    phase = UpdatePhase.checking;
    notifyListeners();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      if (currentVersion.isEmpty) {
        currentVersion = (await PackageInfo.fromPlatform()).version;
      }
      final platform = _testPlatform ?? await DeviceBridge.updatePlatform();
      final endpoint = Uri.https(
        'api.github.com',
        '/repos/$repository/releases/latest',
      );
      final request = await client.getUrl(
        _testRoute?.call(endpoint) ?? endpoint,
      );
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'MBNMovie/$currentVersion',
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );
      if (response.statusCode != 200) {
        throw HttpException('GitHub ${response.statusCode}');
      }
      final body = StringBuffer();
      await for (final chunk
          in response
              .transform(utf8.decoder)
              .timeout(const Duration(seconds: 25))) {
        body.write(chunk);
        if (body.length > 2 * 1024 * 1024) {
          throw const FormatException('Release too large');
        }
      }
      final latest = ReleaseUpdate.fromGitHub(
        jsonDecode(body.toString()) as Map<String, dynamic>,
        repository: repository,
        platform: platform,
      );
      if (latest == null) {
        throw const FormatException(
          'بستهٔ معتبر و سازگار در انتشار موجود نیست.',
        );
      }
      final current = AppVersion.parse(currentVersion);
      if (current == null) {
        throw const FormatException('نسخهٔ برنامه قابل تشخیص نیست.');
      }
      if (latest.version.compareTo(current) <= 0) {
        phase = UpdatePhase.idle;
        release = null;
        requiredRelease = null;
        _package = null;
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('update_required');
        return;
      }
      requiredRelease = latest;
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('update_required', latest.encode());
      // Keep the verified release/package pair together: `release`/`_package`
      // only ever describe an installable build. The newest metadata lives
      // in `latest` until its bytes are downloaded and hash-verified; a
      // failed superseding download therefore cannot invalidate the
      // previously verified fallback (and the mandatory gate never blocks
      // on an uninstallable release).
      final cache = await _cache();
      // Digest is part of the cache identity: republishing a tag cannot reuse stale bytes.
      final target = File(
        p.join(cache.path, '${latest.sha256}-${latest.filename}'),
      );
      if (!await _validPackage(target, latest)) {
        phase = UpdatePhase.downloading;
        progress = null;
        notifyListeners();
        final part = File('${target.path}.part');
        final download = await client.getUrl(
          _testRoute?.call(latest.url) ?? latest.url,
        );
        final stream = await download.close().timeout(
          const Duration(seconds: 30),
        );
        if (stream.statusCode != 200) {
          throw HttpException('Download ${stream.statusCode}');
        }
        final sink = part.openWrite();
        var received = 0;
        var notified = DateTime.now();
        try {
          await for (final chunk in stream.timeout(
            const Duration(seconds: 45),
          )) {
            received += chunk.length;
            if (received > latest.size) {
              throw const FormatException('اندازهٔ فایل نامعتبر است.');
            }
            sink.add(chunk);
            progress = received / latest.size;
            if (DateTime.now().difference(notified).inMilliseconds > 200) {
              notified = DateTime.now();
              notifyListeners();
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (!await _validPackage(part, latest)) {
          throw const FormatException(
            'صحت فایل بروزرسانی تأیید نشد. دوباره تلاش کن.',
          );
        }
        await part.rename(target.path);
      }
      // Replacement verified: only now does it become the installable pair.
      release = latest;
      _package = target;
      phase = UpdatePhase.ready;
      progress = 1;
      // Retain verified notes for the first launch after installation.
      await prefs.setString('update_pending', latest.encode());
    } catch (e) {
      // A previously verified package remains installable during an outage.
      if (canInstallRequiredRelease &&
          _package != null &&
          await _validPackage(_package!, release!)) {
        phase = UpdatePhase.ready;
      } else {
        phase = UpdatePhase.failed;
      }
      error = e is FormatException
          ? e.message
          : 'دسترسی به GitHub یا دانلود قطع شد. دوباره تلاش کن.';
    } finally {
      client.close(force: true);
      _busy = false;
      notifyListeners();
    }
  }

  static Future<bool> _validPackage(File file, ReleaseUpdate release) async {
    if (!await file.exists() || await file.length() != release.size) {
      return false;
    }
    return (await sha256.bind(file.openRead()).first).toString() ==
        release.sha256;
  }

  Future<void> install() async {
    if (_busy ||
        phase != UpdatePhase.ready ||
        !canInstallRequiredRelease ||
        _package == null) {
      return;
    }
    _busy = true;
    phase = UpdatePhase.installing;
    error = null;
    installationPermissionRequired = false;
    notifyListeners();
    try {
      final android =
          Platform.isAndroid || _testRequestInstallPermission != null;
      if (android &&
          !await (_testRequestInstallPermission ??
              DeviceBridge.requestInstallPermission)()) {
        installationPermissionRequired = true;
        phase = UpdatePhase.ready;
        return;
      }
      if (!await _validPackage(_package!, release!)) {
        throw const FormatException('فایل تغییر کرده است؛ دوباره دانلود کن.');
      }
      if (android) {
        final result = await (_testInstallApk ?? DeviceBridge.installApk)(
          _package!.path,
        );
        if (result == 'permission') {
          installationPermissionRequired = true;
          phase = UpdatePhase.ready;
        } else if (result == 'installing') {
          // Android PackageInstaller owns the rest of the transaction. The
          // process is replaced on success; cancellation is reported over the
          // device channel and returns this state to ready for another attempt.
          phase = UpdatePhase.installing;
        } else if (result != 'launched') {
          throw FormatException(
            result == 'signature'
                ? 'امضای این APK با برنامهٔ نصب‌شده متفاوت است. نصب متوقف شد تا اطلاعاتت حفظ شود؛ با پشتیبانی تماس بگیر.'
                : 'بستهٔ نصب معتبر نیست یا نسخهٔ جدیدتری ندارد.',
          );
        } else {
          // Compatibility path used by older integrations and unit tests.
          phase = UpdatePhase.ready;
        }
      } else if (Platform.isWindows) {
        final cache = await _cache();
        final stage = await createInstallStage(cache);
        await compute(extractBundle, (_package!.path, stage.path));
        final root = p.dirname(Platform.resolvedExecutable);
        final updater = File(p.join(root, 'updater.exe'));
        if (!await updater.exists()) {
          throw const FormatException('updater.exe کنار برنامه پیدا نشد.');
        }
        // Run a copy so updater.exe itself can be replaced in the bundle.
        final helper = await updater.copy(
          p.join(stage.path, 'update-helper.exe'),
        );
        final ready = File(p.join(stage.path, 'ready'));
        await Process.start(helper.path, [
          '--apply',
          '$pid',
          root,
          p.join(stage.path, 'MBNMovie'),
          ready.path,
        ], mode: ProcessStartMode.detached);
        for (var attempt = 0; attempt < 100; attempt++) {
          if (await ready.exists()) {
            // Native helper has validated paths and opened this exact process handle.
            await DownloadManager.instance.prepareForUpdate();
            exit(0);
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw const FormatException(
          'آپدیتر آماده نشد؛ برنامه بسته نشد و نسخهٔ فعلی محفوظ است.',
        );
      }
    } catch (e) {
      error = e is FormatException
          ? e.message
          : 'نصب آغاز نشد؛ فضای خالی و دسترسی نوشتن پوشهٔ برنامه را بررسی کن.';
      phase = UpdatePhase.ready;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void handleNativeInstallStatus(String? status) {
    if (status == 'failed' && phase == UpdatePhase.installing) {
      error = 'نصب کامل نشد. برای ادامه دوباره تلاش کن.';
      phase = UpdatePhase.ready;
      notifyListeners();
    }
  }

  @visibleForTesting
  static Future<Directory> createInstallStage(Directory cache) async {
    await cache.create(recursive: true);
    return cache.createTemp('stage-');
  }

  @visibleForTesting
  static void extractBundle((String, String) args) {
    final input = InputFileStream(args.$1);
    try {
      final archive = ZipDecoder().decodeStream(input);
      var total = 0;
      final seen = <String>{};
      for (final entry in archive) {
        if (entry.name == 'MBNMovie/' && !entry.isFile) continue;
        final relative = safeBundlePath(entry.name);
        if (entry.isSymbolicLink) {
          throw const FormatException('پیوند در بسته مجاز نیست.');
        }
        if (!entry.isFile) continue;
        if (!seen.add(relative.toLowerCase())) {
          throw const FormatException('فایل تکراری در بسته');
        }
        total += entry.size;
        if (total > 2 * 1024 * 1024 * 1024 || seen.length > 10000) {
          throw const FormatException('بسته بیش از حد بزرگ است.');
        }
        final destination = p.join(args.$2, 'MBNMovie', relative);
        Directory(p.dirname(destination)).createSync(recursive: true);
        final output = OutputFileStream(destination);
        try {
          entry.writeContent(output);
        } finally {
          output.closeSync();
        }
      }
      for (final required in [
        'mbnmovie.exe',
        'updater.exe',
        'flutter_windows.dll',
        'data/icudtl.dat',
        'data/app.so',
      ]) {
        if (!seen.contains(required)) {
          throw FormatException('بسته ناقص است: $required');
        }
      }
    } finally {
      input.closeSync();
    }
  }
}
