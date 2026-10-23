import 'dart:convert';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'package:window_manager/window_manager.dart';

import 'package:mbnmovie/core/platform_ui.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/screens/main_shell.dart';
import 'package:mbnmovie/services/android_network_trust.dart';
import 'package:mbnmovie/services/device_performance.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/movie_api.dart';
import 'package:mbnmovie/services/network_gate.dart';
import 'package:mbnmovie/widgets/browsable_shelf.dart';
import 'package:mbnmovie/widgets/server_status_gate.dart';

class _TestPaths extends PathProviderWindows {
  _TestPaths(this.path);
  final String path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _SourceClient extends http.BaseClient {
  final inner = http.Client();
  final actions = <String, int>{};
  bool unavailable = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (unavailable) {
      throw const SocketException('QA: all source traffic blocked');
    }
    final action = request.url.queryParameters['action'] ?? 'media';
    actions.update(action, (count) => count + 1, ifAbsent: () => 1);
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 45),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  expect(condition(), true, reason: 'native operation exceeded $timeout');
}

Future<Map<String, Object?>> _play(
  WidgetTester tester,
  MovieContent item,
  MovieEpisode episode,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: MovieTheme.dark,
      home: PlayerScreen(content: item, episode: episode),
    ),
  );
  await tester.pump();
  final player = tester.widget<Video>(find.byType(Video)).controller.player;
  final errors = <String>[];
  final subscription = player.stream.error.listen(errors.add);
  try {
    await _until(
      tester,
      () => player.state.position > const Duration(seconds: 2),
    );
    expect(errors, isEmpty);
    await player.pause();
    final paused = player.state.position;
    await tester.pump(const Duration(milliseconds: 500));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(
      (player.state.position - paused).abs(),
      lessThan(const Duration(milliseconds: 500)),
    );
    await player.play();
    await _until(
      tester,
      () => player.state.position > paused + const Duration(seconds: 1),
    );
    await player.pause();
    await player.seek(const Duration(seconds: 15));
    await _until(
      tester,
      () =>
          (player.state.position - const Duration(seconds: 15)).abs() <
          const Duration(seconds: 1),
      timeout: const Duration(seconds: 8),
    );
    await player.play();
    await _until(
      tester,
      () => player.state.position > const Duration(seconds: 16),
    );
    expect(errors, isEmpty);
    return {
      'titleId': item.id,
      'play': true,
      'seek': true,
      'pauseResume': true,
      'durationSeconds': player.state.duration.inSeconds,
      'positionMs': player.state.position.inMilliseconds,
    };
  } finally {
    await subscription.cancel();
    await tester.pumpWidget(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  HttpOverrides.global = null;
  testWidgets(
    'native catalog and player survive central outage and use saved data without internet',
    (tester) async {
      expect(Platform.isWindows || Platform.isAndroid, true);
      final temp = await Directory.systemTemp.createTemp('mbn-movie-outage-');
      if (Platform.isWindows) {
        SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
          ..pathProvider = _TestPaths(temp.path);
        await windowManager.ensureInitialized();
      } else {
        SharedPreferences.setMockInitialValues({});
      }
      await initializeDeviceLayout();
      await DevicePerformance.initialize();
      await AndroidNetworkTrust.initialize();
      MediaKit.ensureInitialized();
      var bridgeCalls = 0;
      final source = _SourceClient();
      final bridge = MockClient((_) async {
        bridgeCalls++;
        throw const FormatException('QA: central server unavailable');
      });
      final api = MovieApi(client: bridge, offlineClient: source);
      final boundary = GlobalKey();
      final report = <String, Object?>{'platform': Platform.operatingSystem};
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: MovieTheme.dark,
              builder: (context, child) => ServerStatusGate(
                client: MockClient(
                  (_) async => throw const SocketException(
                    'QA: central server unavailable',
                  ),
                ),
                child: child!,
              ),
              home: MainShell(
                email: 'qa@local.invalid',
                auth: MbnAuth(),
                api: api,
                onLogout: () async {},
              ),
            ),
          ),
        );
        await _until(
          tester,
          () => find.text('ادامه دادن').evaluate().isNotEmpty,
        );
        await tester.tap(find.text('ادامه دادن'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'ادامه دادن').last);
        await tester.pump();
        expect(OfflineMode.active, true);
        final callsAtEntry = bridgeCalls;
        await _until(
          tester,
          () => find.byType(BrowsableShelf).evaluate().isNotEmpty,
        );
        expect(tester.takeException(), isNull);
        report['continueOpensLiveHome'] = true;
        final announcement = find.text('متوجه شدم');
        if (announcement.evaluate().isNotEmpty) {
          await tester.tap(announcement.last);
          await tester.pump(const Duration(milliseconds: 500));
        }
        const reportDir = String.fromEnvironment('MBN_QA_REPORT_DIR');
        if (reportDir.isNotEmpty) {
          await tester.pump(const Duration(seconds: 1));
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          await File(
            '$reportDir/movie-offline-${Platform.operatingSystem}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        final home = await api.home();
        expect(home.movies, isNotEmpty);
        expect(home.series, isNotEmpty);
        final catalogCounts = <String, int>{};
        for (final kind in [ContentKind.movie, ContentKind.series]) {
          for (final page in [1, 2]) {
            final items = await api.catalog(kind: kind, page: page);
            expect(items, isNotEmpty);
            catalogCounts['${kind.name}:$page'] = items.length;
          }
        }
        final genres = await api.genres();
        expect(genres, isNotEmpty);
        expect(await api.countries(), isNotEmpty);
        final collections = await api.collections();
        final actors = await api.actors();
        expect(collections, isNotEmpty);
        expect(actors, isNotEmpty);
        final collectionTitles = await api.collectionTitles(collections.first);
        final actorTitles = await api.actorTitles(actors.first);
        final genreTitles = await api.catalogByGroup(
          group: genres.first,
          country: false,
        );
        expect(collectionTitles, isNotEmpty);
        expect(actorTitles, isNotEmpty);
        expect(genreTitles, isNotEmpty);
        expect(await api.actors(page: 2), isNotEmpty);
        expect(await api.searchActors('Keanu'), isNotEmpty);
        expect(await api.advancedFilter(query: 'five feet apart'), isNotEmpty);
        report['sectionNavigation'] = {
          'collectionTitles': collectionTitles.length,
          'actorTitles': actorTitles.length,
          'genreTitles': genreTitles.length,
          'actorPagination': true,
          'actorSearch': true,
          'advancedFilter': true,
        };
        final movie = await api.details(
          (await api.search('five feet apart')).first,
        );
        final series = await api.details(
          (await api.search('the last kingdom')).first,
        );
        expect(movie.seasons, isNotEmpty);
        expect(series.seasons, isNotEmpty);
        expect(movie.downloads, isNotEmpty);
        expect(series.downloads, isNotEmpty);
        await api.comments(movie.id);
        report['catalogPages'] = catalogCounts;
        report['movieFiles'] = movie.downloads.length;
        report['seriesFiles'] = series.downloads.length;
        report['sections'] = home.sections.length;
        report['bridgeCallsAfterEntry'] = bridgeCalls - callsAtEntry;
        expect(bridgeCalls, callsAtEntry);
        // Remove the gate before isolated player probes; its dispose restores
        // normal mode, so explicitly retain the confirmed outage for the probes.
        await tester.pumpWidget(const SizedBox());
        OfflineMode.enter();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('player_gestures_introduced', true);
        final episodes = movie.seasons
            .expand((season) => season.episodes)
            .toList();
        final episode = episodes.firstWhere(
          (item) => item.name.contains('480'),
          orElse: () => episodes.firstWhere(
            (item) => item.name.contains('720'),
            orElse: () => episodes.first,
          ),
        );
        report['livePlayback'] = await _play(tester, movie, episode);
        const fixture = String.fromEnvironment('MBN_QA_LOCAL_MEDIA');
        var localPath = fixture;
        if (fixture.startsWith('http://') || fixture.startsWith('https://')) {
          final fixtureClient = http.Client();
          try {
            final response = await sendBuffered(
              fixtureClient,
              'GET',
              Uri.parse(fixture),
              timeout: const Duration(seconds: 10),
              maxBytes: 2 * 1024 * 1024,
            );
            expect(response.statusCode, 200);
            localPath = '${temp.path}/downloaded-fixture.mp4';
            await File(localPath).writeAsBytes(response.bodyBytes);
          } finally {
            fixtureClient.close();
          }
        }
        source.unavailable = true;
        final restored = MovieApi(client: bridge, offlineClient: source);
        await prefs.reload();
        final cachedHome = await restored.home();
        final cachedSeries = await restored.details(series);
        expect(cachedHome.movies, isNotEmpty);
        expect(cachedSeries.downloads.length, series.downloads.length);
        expect(await restored.search('five feet apart'), isNotEmpty);
        expect(await restored.catalog(kind: ContentKind.movie), isNotEmpty);
        report['totalOutageCache'] = true;
        expect(File(localPath).existsSync(), true);
        report['localPlayback'] = await _play(
          tester,
          movie,
          MovieEpisode(
            id: 'local',
            name: 'Downloaded test clip',
            fileUrl: localPath,
          ),
        );
        expect(tester.takeException(), isNull);
        report['sourceActions'] = source.actions;
        if (reportDir.isNotEmpty) {
          await File(
            '$reportDir/movie-offline-${Platform.operatingSystem}.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
        }
        debugPrint('MBN_MOVIE_OUTAGE ${jsonEncode(report)}');
      } finally {
        await tester.pumpWidget(const SizedBox());
        OfflineMode.leave();
        bridge.close();
        source.close();
        if (Platform.isWindows) await windowManager.setFullScreen(false);
        final safePrefix =
            '${Directory.systemTemp.absolute.path}${Platform.pathSeparator}mbn-movie-outage-';
        if (temp.absolute.path.startsWith(safePrefix)) {
          await temp.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
