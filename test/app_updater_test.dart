import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/services/app_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'release_update_test.dart' show releaseJson;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Real loopback HTTP exercises streaming/checksum behavior; no internet used.
  HttpOverrides.global = null;
  late HttpServer server;
  late Directory directory;
  var availableVersion = '1.2.0';
  var offline = false;
  var corrupt = false;
  var downloads = 0;
  final bytes = utf8.encode('verified-package');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    availableVersion = '1.2.0';
    offline = false;
    corrupt = false;
    downloads = 0;
    directory = await Directory.systemTemp.createTemp('mbnmovie-update-test-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (offline) {
        request.response.statusCode = 503;
      } else if (request.uri.path.contains('/latest')) {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            releaseJson(
              version: availableVersion,
              digest: 'sha256:${sha256.convert(bytes)}',
              size: bytes.length,
            ),
          ),
        );
      } else {
        downloads++;
        request.response.add(corrupt ? List.filled(bytes.length, 0) : bytes);
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });
  AppUpdater updater([String version = '1.1.0']) => AppUpdater.testing(
    currentVersion: version,
    cacheDirectory: directory,
    platform: 'Windows-x64',
    route: (uri) => Uri.http('127.0.0.1:${server.port}', uri.path),
  );

  test(
    'downloads once, verifies, and reuses staged update on every launch',
    () async {
      final first = updater();
      await first.initialize();
      expect(first.phase, UpdatePhase.ready);
      expect(downloads, 1);
      final second = updater();
      await second.initialize();
      expect(second.phase, UpdatePhase.ready);
      expect(downloads, 1);
      offline = true;
      final offlineLaunch = updater();
      await offlineLaunch.initialize();
      expect(offlineLaunch.phase, UpdatePhase.ready);
    },
  );
  test('superseded update is replaced with newest stable release', () async {
    final instance = updater();
    await instance.initialize();
    availableVersion = '1.3.0';
    await instance.check();
    expect(instance.release?.version.toString(), '1.3.0');
    expect(downloads, 2);
  });
  test(
    'failed superseding download keeps the previous verified fallback',
    () async {
      final instance = updater();
      await instance.initialize();
      expect(instance.phase, UpdatePhase.ready);
      expect(instance.release?.version.toString(), '1.2.0');
      // A newer release appears but its bytes fail verification.
      availableVersion = '1.3.0';
      corrupt = true;
      await instance.check();
      // The previously verified 1.2.0 package must remain installable;
      // the failed 1.3.0 bytes must never become the installable pair.
      expect(instance.phase, UpdatePhase.ready);
      expect(instance.release?.version.toString(), '1.2.0');
      expect(instance.error, isNotNull);
    },
  );
  test('checksum mismatch never becomes installable and can retry', () async {
    corrupt = true;
    final instance = updater();
    await instance.initialize();
    expect(instance.phase, UpdatePhase.failed);
    corrupt = false;
    await instance.check();
    expect(instance.phase, UpdatePhase.ready);
  });
  test(
    'permission denial preserves package and retry installs only after grant',
    () async {
      final calls = <String>[];
      var granted = false;
      final instance = AppUpdater.testing(
        currentVersion: '1.1.0',
        cacheDirectory: directory,
        platform: 'Windows-x64',
        route: (uri) => Uri.http('127.0.0.1:${server.port}', uri.path),
        requestInstallPermission: () async {
          calls.add('permission');
          return granted;
        },
        installApk: (_) async {
          calls.add('install');
          return 'launched';
        },
      );
      await instance.initialize();
      await instance.install();
      expect(calls, ['permission']);
      expect(instance.error, isNull);
      expect(instance.phase, UpdatePhase.ready);
      expect(instance.installationPermissionRequired, isTrue);
      granted = true;
      await instance.install();
      expect(calls, ['permission', 'permission', 'install']);
      expect(instance.installationPermissionRequired, isFalse);
      expect(instance.error, isNull);
      expect(downloads, 1);
    },
  );
  test(
    'does not downgrade; notes only shown after version really changes',
    () async {
      final old = updater();
      await old.initialize();
      final unchanged = updater();
      await unchanged.initialize();
      expect(unchanged.installedNotes, isNull);
      final installed = updater('1.2.0');
      await installed.initialize();
      expect(installed.installedNotes, contains('فارسی'));
      expect(installed.phase, UpdatePhase.idle);
      final next = updater('1.2.0');
      await next.initialize();
      expect(next.installedNotes, isNull);
    },
  );
  test('concurrent checks do not duplicate the download', () async {
    final instance = updater();
    await Future.wait([instance.check(), instance.check()]);
    expect(downloads, 1);
    expect(instance.phase, UpdatePhase.ready);
  });
  test('failed native install returns the mandatory flow to retry', () {
    final instance = updater()..phase = UpdatePhase.installing;
    instance.handleNativeInstallStatus('failed');
    expect(instance.phase, UpdatePhase.ready);
    expect(instance.error, contains('نصب کامل نشد'));
  });
  test(
    'PackageInstaller transaction keeps the mandatory gate installing',
    () async {
      final instance = AppUpdater.testing(
        currentVersion: '1.1.0',
        cacheDirectory: directory,
        platform: 'Windows-x64',
        route: (uri) => Uri.http('127.0.0.1:${server.port}', uri.path),
        requestInstallPermission: () async => true,
        installApk: (_) async => 'installing',
      );
      await instance.initialize();
      await instance.install();
      expect(instance.phase, UpdatePhase.installing);
      expect(instance.error, isNull);
    },
  );
}
