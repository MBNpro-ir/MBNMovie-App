import '../core/app_platform.dart';

import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';
import 'device_bridge.dart';
import 'browser_features.dart';
import '../core/external_player_link.dart';
import 'package:flutter/foundation.dart';

enum ExternalVideoPlayer { vlc, mxPlayer, mxPlayerPro }

enum ExternalLaunchResult {
  launched,
  missing,
  unsupported,
  unavailable,
  failed,
}

class ExternalApps {
  const ExternalApps._();

  static const admStoreUrl =
      'https://play.google.com/store/apps/details?id=com.dv.adm';
  static const idmDownloadUrl =
      'https://download.internetdownloadmanager.com/idman643build10.exe';
  static const vlcDownloadUrl = 'https://www.videolan.org/vlc/';
  static const mxPlayerStoreUrl =
      'https://play.google.com/store/apps/details?id=com.mxtech.videoplayer.ad';
  static const mxPlayerProStoreUrl =
      'https://play.google.com/store/apps/details?id=com.mxtech.videoplayer.pro';

  static List<ExternalVideoPlayer> get availablePlayers => [
    if (Platform.isWindows || Platform.isIOS || Platform.isAndroid || kIsWeb)
      ExternalVideoPlayer.vlc,
    if (Platform.isAndroid || (kIsWeb && BrowserFeatures.isAndroidBrowser)) ...[
      ExternalVideoPlayer.mxPlayer,
      ExternalVideoPlayer.mxPlayerPro,
    ],
  ];

  static String playerName(ExternalVideoPlayer player) => switch (player) {
    ExternalVideoPlayer.vlc => 'VLC',
    ExternalVideoPlayer.mxPlayer => 'MX Player',
    ExternalVideoPlayer.mxPlayerPro => 'MX Player Pro',
  };

  static String playerInstallUrl(ExternalVideoPlayer player) =>
      switch (player) {
        ExternalVideoPlayer.vlc =>
          Platform.isIOS || (kIsWeb && BrowserFeatures.isAppleMobile)
              ? 'https://apps.apple.com/app/vlc-media-player/id650377962'
              : Platform.isAndroid ||
                    (kIsWeb && BrowserFeatures.isAndroidBrowser)
              ? 'https://play.google.com/store/apps/details?id=org.videolan.vlc'
              : vlcDownloadUrl,
        ExternalVideoPlayer.mxPlayer => mxPlayerStoreUrl,
        ExternalVideoPlayer.mxPlayerPro => mxPlayerProStoreUrl,
      };

  static Future<ExternalLaunchResult> playVideo({
    required ExternalVideoPlayer player,
    required String url,
    required String title,
  }) async {
    if (kIsWeb || Platform.isIOS) {
      final uri = externalPlayerLink(
        player: player.name,
        platform: BrowserFeatures.isAppleMobile || Platform.isIOS
            ? 'ios'
            : BrowserFeatures.isAndroidBrowser
            ? 'android'
            : 'windows',
        url: url,
        title: title,
        appScheme: 'mbnmovie-player',
      );
      if (uri == null) return ExternalLaunchResult.unsupported;
      try {
        if (kIsWeb) {
          return BrowserFeatures.openExternal(uri)
              ? ExternalLaunchResult.launched
              : ExternalLaunchResult.failed;
        }
        return await launchUrl(uri, mode: LaunchMode.externalApplication)
            ? ExternalLaunchResult.launched
            : ExternalLaunchResult.missing;
      } catch (_) {
        return ExternalLaunchResult.failed;
      }
    }
    if (Platform.isAndroid) {
      final packageName = switch (player) {
        ExternalVideoPlayer.vlc => 'org.videolan.vlc',
        ExternalVideoPlayer.mxPlayer => 'com.mxtech.videoplayer.ad',
        ExternalVideoPlayer.mxPlayerPro => 'com.mxtech.videoplayer.pro',
      };
      final intent = AndroidIntent(
        action: 'action_view',
        data: url,
        type: _videoMime(url),
        package: packageName,
        arguments: {'title': title},
      );
      try {
        if (await intent.canResolveActivity() != true) {
          return ExternalLaunchResult.missing;
        }
        await intent.launch();
        return ExternalLaunchResult.launched;
      } catch (_) {
        return ExternalLaunchResult.failed;
      }
    }

    if (Platform.isWindows && player == ExternalVideoPlayer.vlc) {
      final executable = _findWindowsExecutable([
        r'C:\Program Files\VideoLAN\VLC\vlc.exe',
        r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
      ]);
      if (executable == null) return ExternalLaunchResult.missing;
      try {
        await Process.start(executable, [
          url,
          '--meta-title=$title',
        ], mode: ProcessStartMode.detached);
        return ExternalLaunchResult.launched;
      } catch (_) {
        return ExternalLaunchResult.failed;
      }
    }
    return ExternalLaunchResult.unsupported;
  }

  static Future<ExternalLaunchResult> playLocalVideo({
    required ExternalVideoPlayer player,
    required String path,
    required String title,
  }) async {
    if (!await File(path).exists()) return ExternalLaunchResult.unavailable;
    if (Platform.isAndroid) {
      try {
        final result = await DeviceBridge.channel.invokeMethod<String>(
          'playLocalVideo',
          {'path': path, 'player': player.name, 'title': title},
        );
        return result == 'launched'
            ? ExternalLaunchResult.launched
            : result == 'missing'
            ? ExternalLaunchResult.missing
            : ExternalLaunchResult.failed;
      } catch (_) {
        return ExternalLaunchResult.failed;
      }
    }
    // Launch VLC directly with an argument list, never cmd/start or a shell.
    return playVideo(player: player, url: path, title: title);
  }

  static Future<ExternalLaunchResult> downloadOne({
    required String url,
    required String fileName,
  }) => downloadAll([(url: url, fileName: fileName)]);

  static Future<ExternalLaunchResult> downloadAll(
    List<({String url, String fileName})> items,
  ) async {
    final valid = items.where((item) => item.url.trim().isNotEmpty).toList();
    if (valid.isEmpty) return ExternalLaunchResult.failed;

    if (Platform.isAndroid) {
      final target = await _resolveAdm(valid.first);
      if (target == null) return ExternalLaunchResult.missing;
      try {
        // This is the same contract used by the original client. ADM receives
        // the raw URL and handles CDN redirects itself.
        for (final item in valid) {
          await AndroidIntent(
            action: 'android.intent.action.VIEW',
            data: item.url,
            package: target.packageName,
            arguments: {'filename': item.fileName},
          ).launch();
          await Future<void>.delayed(const Duration(milliseconds: 160));
        }
        return ExternalLaunchResult.launched;
      } catch (_) {
        return ExternalLaunchResult.failed;
      }
    }

    if (Platform.isWindows) {
      // IDM exposes some 301/302 responses as an invalid HTTP reply. Resolve
      // and validate those links before passing them to IDMan.exe.
      final resolved = <String?>[];
      for (var offset = 0; offset < valid.length; offset += 4) {
        final end = (offset + 4).clamp(0, valid.length);
        resolved.addAll(
          await Future.wait(valid.sublist(offset, end).map(_resolveDownload)),
        );
      }
      if (resolved.any((item) => item == null)) {
        return ExternalLaunchResult.unavailable;
      }
      final ready = [
        for (var i = 0; i < valid.length; i++)
          (url: resolved[i]!, fileName: valid[i].fileName),
      ];
      final idm = _findWindowsExecutable([
        r'C:\Program Files (x86)\Internet Download Manager\IDMan.exe',
        r'C:\Program Files\Internet Download Manager\IDMan.exe',
      ]);
      if (idm == null) return ExternalLaunchResult.missing;
      try {
        if (ready.length == 1) {
          await Process.start(idm, [
            '/d',
            ready.single.url,
            '/f',
            ready.single.fileName,
          ], mode: ProcessStartMode.detached);
        } else {
          for (final item in ready) {
            await Process.run(idm, [
              '/d',
              item.url,
              '/f',
              item.fileName,
              '/a',
              '/n',
            ]);
          }
          await Process.start(idm, ['/s'], mode: ProcessStartMode.detached);
        }
        return ExternalLaunchResult.launched;
      } catch (_) {
        return ExternalLaunchResult.failed;
      }
    }
    return ExternalLaunchResult.unsupported;
  }

  static Future<void> openOfficialDownload(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static Future<_AdmTarget?> _resolveAdm(
    ({String url, String fileName}) sample,
  ) async {
    for (final target in const [
      _AdmTarget('com.dv.adm'),
      _AdmTarget('com.dv.adm.pay'),
    ]) {
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: sample.url,
        package: target.packageName,
      );
      if (await intent.canResolveActivity() == true) return target;
    }
    return null;
  }

  static Future<String?> _resolveDownload(
    ({String url, String fileName}) item,
  ) async {
    final source = Uri.tryParse(item.url.trim());
    if (source == null || !source.hasScheme) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(source)
          .timeout(const Duration(seconds: 10));
      request.headers
        ..set(HttpHeaders.rangeHeader, 'bytes=0-0')
        ..set(HttpHeaders.userAgentHeader, 'MBNMovie/1.0')
        ..set(HttpHeaders.acceptHeader, '*/*');
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final ok =
          response.statusCode == HttpStatus.ok ||
          response.statusCode == HttpStatus.partialContent;
      final finalUri = response.redirects.isEmpty
          ? source
          : response.redirects.last.location;
      return ok ? finalUri.toString() : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String? _findWindowsExecutable(List<String> candidates) {
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  static String _videoMime(String url) =>
      url.toLowerCase().contains('.m3u8') ? 'application/x-mpegURL' : 'video/*';
}

class _AdmTarget {
  const _AdmTarget(this.packageName);
  final String packageName;
}
