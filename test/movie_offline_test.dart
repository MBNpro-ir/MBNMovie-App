import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/screens/main_shell.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/movie_api.dart';
import 'package:mbnmovie/services/network_gate.dart';
import 'package:mbnmovie/widgets/server_status_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/movie_catalog_fixtures.dart';

MovieContent summary(String id) => MovieContent(
  id: id,
  title: id == offlineMovieId ? 'Fresh Movie' : 'Fresh Series',
  subtitle: '',
  description: '',
  year: 2026,
  rating: 7,
  kind: id == offlineMovieId ? ContentKind.movie : ContentKind.series,
  colors: const [Colors.indigo, Colors.black],
  genres: const [],
);

class _StalledClient extends http.BaseClient {
  _StalledClient(this.phase);
  final String phase;
  final started = Completer<void>();
  final aborted = Completer<void>();
  final response = Completer<http.StreamedResponse>();
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    if (request.url.queryParameters['action'] == phase) {
      if (!started.isCompleted) started.complete();
      if (request is http.Abortable) {
        request.abortTrigger?.then((_) {
          if (!aborted.isCompleted) aborted.complete();
        });
      }
      return response.future;
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(catalogReply('login', const {})))),
      200,
    );
  }

  void finish() {
    response.complete(
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(catalogReply('vitrin', const {})))),
        200,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineMode.leave();
  });
  tearDown(() => OfflineMode.leave());

  test(
    'fresh native catalog sections and uncached episodes work without the central server',
    () async {
      OfflineMode.enter();
      var centralCalls = 0, centralSearches = 0, logins = 0, reads = 0;
      final api =
          MovieApi(
            client: MockClient((_) async {
              centralCalls++;
              throw StateError('central server must not be contacted');
            }),
            offlineClient: MockClient((request) async {
              expect(request.url.host, 'googfilmazappfordownfilmmedis.xyz');
              expect(request.headers.containsKey('authorization'), false);
              expect(request.headers.containsKey('cookie'), false);
              expect(request.bodyFields['user_name'], isEmpty);
              expect(request.bodyFields.containsKey('pass'), false);
              if (request.url.queryParameters['action'] == 'login') {
                logins++;
                expect(request.bodyFields['token'], isEmpty);
              } else {
                reads++;
                expect(request.bodyFields['token'], 'guest-token');
              }
              return catalogResponse(request);
            }),
            indexLoader: () async => '[]',
          )..bindDelfanSession(
            mobile: 'private-user',
            password: 'private-password',
          );
      api.catalogRequest = (_, _) async {
        centralSearches++;
        throw StateError('central search must not be used');
      };
      final home = await api.home();
      expect(home.movies.single.id, offlineMovieId);
      expect(home.series.single.id, offlineSeriesId);
      expect(home.sections, hasLength(3));
      expect(home.actors.single.id, '3');
      expect(home.collections.single.id, '4');
      expect(home.tags.single.id, '5');
      expect(home.genres.single.id, '6');
      expect(home.countries.single.id, '7');
      for (final kind in [ContentKind.movie, ContentKind.series]) {
        for (final page in [1, 2]) {
          expect(await api.catalog(kind: kind, page: page), isNotEmpty);
        }
      }
      expect(await api.collections(), isNotEmpty);
      expect(await api.collectionTitles(home.collections.single), isNotEmpty);
      expect(
        await api.titlesByCategory(
          const MovieBanner(imageUrl: '', category: '7', title: 'Country'),
        ),
        isNotEmpty,
      );
      expect(await api.tags(), isNotEmpty);
      for (final country in [false, true]) {
        expect(await api.filterOptions(country: country), isNotEmpty);
        expect(
          await api.catalogByGroup(
            group: country ? home.countries.single : home.genres.single,
            country: country,
          ),
          isNotEmpty,
        );
      }
      expect(await api.actors(page: 2), isNotEmpty);
      expect(await api.searchActors('Test'), isNotEmpty);
      expect((await api.actorDetails(home.actors.single)).titles, isNotEmpty);
      expect(await api.advancedFilter(query: 'new upstream title'), isNotEmpty);
      expect(await api.search('new upstream title'), isNotEmpty);
      final movie = await api.details(summary(offlineMovieId));
      final series = await api.details(summary(offlineSeriesId));
      expect(
        movie.seasons.single.episodes.single.fileUrl,
        'https://cdn.example/movie.mp4',
      );
      expect(movie.downloads, hasLength(1));
      expect(series.seasons.single.episodes, hasLength(2));
      expect(series.downloads, hasLength(2));
      expect(await api.comments(offlineMovieId), hasLength(1));
      expect(
        logins,
        reads,
        reason: 'each catalog action uses a fresh guest nonce',
      );
      expect(centralCalls, 0);
      expect(centralSearches, 0);
    },
  );

  for (final phase in ['login', 'vitrin']) {
    test(
      'confirming offline interrupts a stalled bridge $phase and resumes queued catalog reads',
      () async {
        final bridge = _StalledClient(phase);
        var directCalls = 0;
        final api = MovieApi(
          client: bridge,
          offlineClient: MockClient((r) async {
            directCalls++;
            return catalogResponse(r);
          }),
          indexLoader: () async => '[]',
        );
        final home = api.home();
        await bridge.started.future;
        final movies = api.catalog(kind: ContentKind.movie);
        OfflineMode.enter();
        expect(
          (await home.timeout(const Duration(seconds: 1))).movies,
          isNotEmpty,
        );
        expect(await movies.timeout(const Duration(seconds: 1)), isNotEmpty);
        await bridge.aborted.future.timeout(const Duration(seconds: 1));
        expect(directCalls, 4);
        final calls = bridge.calls;
        bridge.finish();
        await Future<void>.delayed(Duration.zero);
        expect(
          bridge.calls,
          calls,
          reason: 'late bridge results cannot resume the old route',
        );
      },
    );
  }

  test(
    'a catalog switched to guest mid-request cannot poison the bridge cache',
    () async {
      final started = Completer<void>();
      final stalled = Completer<http.Response>();
      var bridgePages = 0;
      final api = MovieApi(
        client: MockClient((r) async {
          if (r.url.queryParameters['action'] == 'movie_list') {
            bridgePages++;
            if (bridgePages == 1) {
              started.complete();
              return stalled.future;
            }
          }
          return catalogResponse(r);
        }),
        offlineClient: MockClient((r) async => catalogResponse(r)),
      );
      final first = api.catalog(kind: ContentKind.movie);
      await started.future;
      OfflineMode.enter();
      expect(await first.timeout(const Duration(seconds: 1)), isNotEmpty);
      OfflineMode.leave();
      expect(await api.catalog(kind: ContentKind.movie), isNotEmpty);
      expect(bridgePages, 2);
      stalled.complete(http.Response('{}', 200));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'server recovery cancels direct reads and restores the authenticated bridge',
    () async {
      OfflineMode.enter();
      final direct = _StalledClient('login');
      final bridgeCalls = <http.Request>[];
      final api =
          MovieApi(
            offlineClient: direct,
            client: MockClient((r) async {
              bridgeCalls.add(r);
              return catalogResponse(r);
            }),
            indexLoader: () async => '[]',
          )..bindDelfanSession(
            mobile: 'private-user',
            password: 'private-password',
          );
      final home = api.home();
      await direct.started.future;
      OfflineMode.leave();
      expect(
        (await home.timeout(const Duration(seconds: 1))).movies,
        isNotEmpty,
      );
      await direct.aborted.future.timeout(const Duration(seconds: 1));
      expect(bridgeCalls.first.bodyFields['user_name'], 'private-user');
      expect(bridgeCalls.first.bodyFields['pass'], 'private-password');
      expect(direct.calls, 1);
      direct.finish();
    },
  );

  test(
    'offline source refresh adds episodes and survives a restart and a total network outage',
    () async {
      OfflineMode.enter();
      var count = 2;
      final api = MovieApi(
        client: MockClient((_) async => throw StateError('central down')),
        offlineClient: MockClient(
          (r) async => catalogResponse(r, episodeCount: count),
        ),
        indexLoader: () async => '[]',
      );
      await api.home();
      expect(
        (await api.details(summary(offlineSeriesId))).seasons.single.episodes,
        hasLength(2),
      );
      count = 3;
      expect(
        (await api.details(summary(offlineSeriesId))).seasons.single.episodes,
        hasLength(3),
      );
      final fresh = MovieApi(
        client: MockClient((_) async => throw StateError('central down')),
        offlineClient: MockClient((_) async => throw StateError('no internet')),
        indexLoader: () async => jsonEncode([
          {
            'id': offlineMovieId,
            'title': 'Fresh Movie',
            'kind': 'movie',
            'genres': 'Drama',
            'countries': 'Canada',
          },
          {
            'id': offlineSeriesId,
            'title': 'Fresh Series',
            'kind': 'serie',
            'genres': 'Drama',
            'countries': 'Canada',
          },
        ]),
      );
      final restoredHome = await fresh.home();
      expect(restoredHome.movies, isNotEmpty);
      expect(restoredHome.actors, isNotEmpty);
      expect(await fresh.catalog(kind: ContentKind.series), hasLength(1));
      expect(
        (await fresh.details(summary(offlineSeriesId))).seasons.single.episodes,
        hasLength(3),
      );
      expect(await fresh.comments(offlineSeriesId), hasLength(1));
      expect(
        await fresh.catalogByGroup(
          group: restoredHome.genres.single,
          country: false,
        ),
        hasLength(2),
      );
    },
  );

  for (final bad in ['empty', 'wrong-id', 'malformed']) {
    test(
      '$bad refresh cannot destroy the last complete episode list',
      () async {
        OfflineMode.enter();
        var valid = true;
        final api = MovieApi(
          offlineClient: MockClient((r) async {
            if (r.url.queryParameters['action'] != 'detials' || valid) {
              return catalogResponse(r);
            }
            if (bad == 'malformed') return http.Response('{', 200);
            final data = catalogReply('detials', {'id': offlineSeriesId});
            final row = (data['detiles'] as List).single as Map;
            if (bad == 'empty') row['download_link'] = [];
            if (bad == 'wrong-id') row['id'] = 'different-title';
            return http.Response(jsonEncode(data), 200);
          }),
        );
        await api.details(summary(offlineSeriesId));
        valid = false;
        expect(
          (await api.details(summary(offlineSeriesId))).seasons.single.episodes,
          hasLength(2),
        );
        final restarted = MovieApi(
          offlineClient: MockClient(
            (_) async => throw StateError('no network'),
          ),
        );
        expect(
          (await restarted.details(
            summary(offlineSeriesId),
          )).seasons.single.episodes,
          hasLength(2),
        );
      },
    );
  }

  test(
    'first launch without internet keeps the index and category filters but does not invent playable links',
    () async {
      OfflineMode.enter();
      final api = MovieApi(
        offlineClient: MockClient((_) async => throw StateError('no network')),
        indexLoader: () async => jsonEncode([
          {
            'id': offlineMovieId,
            'title': 'Fresh Movie',
            'kind': 'movie',
            'genres': 'Drama',
            'countries': 'Canada',
          },
        ]),
      );
      expect((await api.home()).movies, hasLength(1));
      expect((await api.genres()).single.name, 'Drama');
      expect((await api.countries()).single.name, 'Canada');
      expect(
        await api.catalogByGroup(
          group: (await api.genres()).single,
          country: false,
        ),
        hasLength(1),
      );
      await expectLater(
        api.details(summary(offlineMovieId)),
        throwsA(isA<MovieApiException>()),
      );
    },
  );

  test(
    'empty home refresh preserves saved shelves and caches only catalog data',
    () async {
      OfflineMode.enter();
      var empty = false;
      final api = MovieApi(
        offlineClient: MockClient((r) async {
          if (r.url.queryParameters['action'] != 'vitrin') {
            return catalogResponse(r);
          }
          final data = empty
              ? <String, dynamic>{}
              : catalogReply('vitrin', const {});
          data['infos'] = [
            {'token': 'never-cache-this-session'},
          ];
          return http.Response(jsonEncode(data), 200);
        }),
      );
      expect((await api.home()).movies, isNotEmpty);
      empty = true;
      expect((await api.home()).movies.single.id, offlineMovieId);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('mbnmovie_home_cache_v1'),
        isNot(contains('never-cache-this-session')),
      );
    },
  );

  for (final detail in [false, true]) {
    testWidgets(
      'Continue refreshes an already failed ${detail ? 'detail' : 'home'} screen',
      (tester) async {
        final api = MovieApi(
          client: MockClient(
            (_) async => throw const FormatException('central down'),
          ),
          offlineClient: MockClient((r) async => catalogResponse(r)),
          indexLoader: () async => '[]',
        );
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => ServerStatusGate(
              client: MockClient(
                (_) async => throw const FormatException('central down'),
              ),
              child: child!,
            ),
            home: detail
                ? DetailScreen(
                    content: summary(offlineMovieId),
                    api: api,
                    isFavorite: false,
                    onFavoriteChanged: (_) {},
                    heroTag: 'test',
                  )
                : MainShell(
                    email: 'test@local.invalid',
                    auth: MbnAuth(),
                    api: api,
                    onLogout: () async {},
                  ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        await tester.tap(find.text('ادامه دادن'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'ادامه دادن').last);
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 2));
        expect(OfflineMode.active, true);
        expect(find.text('Fresh Movie'), findsWidgets);
        expect(find.textContaining('قابل خواندن نیست'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
