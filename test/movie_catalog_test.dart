import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/services/movie_api.dart';

void main() {
  test('guest search finds The Last Kingdom in both languages when API rejects filtering', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final api = MovieApi(client: MockClient((request) async {
      if (request.url.queryParameters['action'] == 'login') {
        return http.Response(jsonEncode({
          'infos': [{'auth': 'guest'}], 'q1': 1, 'q2': 2,
        }), 200);
      }
      return http.Response(jsonEncode({'state_all': 'F', 'msg': 'guest'}), 200);
    }));
    for (final query in ['The Last Kingdom', 'آخرین پادشاهی']) {
      expect((await api.search(query)).map((item) => item.id), contains('8315'));
      expect((await api.advancedFilter(query: query)).map((item) => item.id),
          contains('8315'));
    }
  });

  test(
    'bundled catalog finds every The Office series by original title',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final catalog = await rootBundle.loadString('assets/catalog_index.json');
      expect(catalog, contains('The Office'));
      final api = MovieApi(
        client: MockClient((request) async {
          if (request.url.queryParameters['action'] == 'login') {
            return http.Response(
              jsonEncode({
                'infos': [
                  {'auth': 'guest'},
                ],
                'q1': 1,
                'q2': 2,
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'state_all': 'T', 'all': []}), 200);
        }),
      );
      final matches = await api.search('the office');
      expect(
        matches.map((item) => item.id),
        containsAll(['32040', '23349', '7632']),
      );
      expect(matches.every((item) => item.kind == ContentKind.series), isTrue);
    },
  );

  test(
    'country filter keeps The Office results inside the selected country',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final client = MockClient((request) async {
        final action = request.url.queryParameters['action'];
        if (action == 'login') {
          return http.Response(
            jsonEncode({
              'infos': [
                {'auth': 'guest'},
              ],
              'q1': 1,
              'q2': 2,
            }),
            200,
          );
        }
        if (action == 'vitrin') {
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'state_all': 'T',
                'genre': [
                  {'genre_id': '13', 'name': 'کمدی'},
                ],
                'country': [
                  {'country_id': '1', 'name': 'امریکا'},
                ],
              }),
            ),
            200,
          );
        }
        return http.Response(jsonEncode({'state_all': 'T', 'all': []}), 200);
      });
      final api = MovieApi(client: client);
      final matches = await api.advancedFilter(
        query: 'the office',
        country: '1',
      );
      expect(matches.map((item) => item.id), contains('7632'));
      expect(matches.map((item) => item.id), isNot(contains('23349')));
      expect(matches.map((item) => item.id), isNot(contains('32040')));
    },
  );

  test('each catalog action obtains a fresh one-use guest auth', () async {
    var issued = 0;
    final consumed = <String>{};
    final client = MockClient((request) async {
      final action = request.url.queryParameters['action']!;
      if (action == 'login') {
        issued++;
        return http.Response(
          jsonEncode({
            'infos': [
              {'auth': 'guest-$issued'},
            ],
            'q1': 1,
            'q2': 2,
            'night_mode': '',
            'tx_size': '1',
          }),
          200,
        );
      }
      final token = RegExp(
        r'guest-\d+',
      ).firstMatch(request.bodyFields['body'] ?? '')?.group(0);
      if (token == null || !consumed.add(token)) {
        return http.Response(
          jsonEncode({'state_all': 'F', 'msg': 'expired'}),
          200,
        );
      }
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'state_all': 'T',
            'NewMovie': [],
            'NewSerie': [],
            'genre': [],
            'country': [],
            'casts': [],
            'updated_serie': [],
            'vige': [],
            'Nostalgy': [],
            'detiles': [
              {'id': 1, 'title': 'نمونه', 'description': 'شرح'},
            ],
          }),
        ),
        200,
      );
    });
    final api = MovieApi(client: client);
    await api.home();
    await api.details(
      const MovieContent(
        id: '1',
        title: 'نمونه',
        subtitle: '',
        description: '',
        year: 2026,
        rating: 0,
        kind: ContentKind.movie,
        colors: [],
        genres: [],
      ),
    );
    expect(issued, 2);
    expect(consumed, {'guest-1', 'guest-2'});
  });

  test('guest catalog retains the existing home and detail models', () async {
    final actions = <String>[];
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.bodyFields['apname'], 'MBNMovie');
      final action = request.url.queryParameters['action']!;
      actions.add(action);
      if (action == 'login') {
        return http.Response(
          jsonEncode({
            'infos': [
              {'auth': 'sample'},
            ],
            'q1': 1,
            'q2': 2,
            'night_mode': '',
            'tx_size': '1',
          }),
          200,
        );
      }
      if (action == 'vitrin') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'NewMovie': [
                {
                  'videos_id': 1,
                  'title': 'فیلم نمونه',
                  'year': '2026',
                  'thumbnail_url': 'http://example.test/poster.jpg',
                },
                {'videos_id': 9, 'title': 'Adult XXX'},
              ],
              'NewSerie': [
                {'videos_id': 2, 'title': 'سریال نمونه'},
              ],
              'updated_serie': [],
              'vige': [],
              'Nostalgy': [],
              'genre': [
                {'genre_id': 3, 'name': 'درام'},
              ],
              'country': [
                {'country_id': 4, 'name': 'ایران'},
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (action == 'detials') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'detiles': [
                {
                  'id': 2,
                  'title': 'سریال نمونه',
                  'is_movie': '0',
                  'description':
                      'نام اصلی : Example<br>ژانرها : درام<br>خلاصه: شرح <b>سریال</b>',
                  'genre': 'درام',
                  'country': 'ایران',
                  'download_link': [
                    {
                      'session_title': 'فصل ۱',
                      'links': [
                        {
                          'id': 10,
                          'name': 'قسمت ۱ - کیفیت ۷۲۰',
                          'link': 'http://example.test/episode.mkv',
                          'video_size': '100 مگابایت',
                        },
                      ],
                    },
                  ],
                },
              ],
              'comments': [
                {'id': 7, 'name': 'کاربر', 'des': 'دیدنی بود'},
              ],
              'casts': [],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = MovieApi(client: client);
    final home = await api.home();
    expect(home.movies.map((item) => item.id), ['1']);
    expect(home.series.single.kind, ContentKind.series);
    expect((await api.genres()).single.name, 'درام');
    final detail = await api.details(home.series.single);
    expect(detail.description, contains('نام اصلی : Example'));
    expect(detail.description, contains('شرح سریال'));
    expect(detail.alternateTitles, ['Example']);
    expect(
      detail.seasons.single.episodes.single.fileUrl,
      'http://example.test/episode.mkv',
    );
    expect((await api.comments(detail.id)).single.text, 'دیدنی بود');
    expect(actions, contains('vitrin'));
    expect(actions, contains('detials'));
  });

  test('actors continue from the first cast_list page after home', () async {
    final pagenos = <String>[];
    final client = MockClient((request) async {
      final action = request.url.queryParameters['action']!;
      if (action == 'login') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'infos': [
                {'auth': 'sample'},
              ],
              'q1': 1,
              'q2': 2,
              'night_mode': '',
              'tx_size': '1',
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (action == 'vitrin') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'NewMovie': [],
              'NewSerie': [],
              'updated_serie': [],
              'vige': [],
              'Nostalgy': [],
              'casts': [
                {'id': '10', 'name': 'بازیگر ویترین', 'pic_url': ''},
              ],
              'genre': [],
              'country': [],
              'Collection': [],
              'banner_cnt': [],
              'mazamin': [],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (action.startsWith('cast_list')) {
        pagenos.add(request.url.queryParameters['pageno'] ?? '');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'casts': [
                {'id': '11', 'name': 'بازیگر فهرست', 'pic_url': ''},
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = MovieApi(client: client);
    final first = await api.actors(page: 1);
    expect(first.single.id, '10');
    final second = await api.actors(page: 2);
    expect(second.single.id, '11');
    // صفحه دوم بازیگران همان صفحه اول cast_list است تا چیزی جا نماند.
    expect(pagenos, ['1']);
  });

  test('actor details include biography and role', () async {
    final client = MockClient((request) async {
      final action = request.url.queryParameters['action']!;
      if (action == 'login') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'infos': [
                {'auth': 'sample'},
              ],
              'q1': 1,
              'q2': 2,
              'night_mode': '',
              'tx_size': '1',
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (action.startsWith('show_movie_cast')) {
        expect(request.bodyFields['cast_id'], '10963');
        expect(request.bodyFields['cast_type'], 'cast');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'bio': 'بازیگر آمریکایی',
              'movie_list': [
                {
                  'videos_id': '5',
                  'title': 'فیلم بازیگر',
                  'year': '2024',
                  'thumbnail_url': 'http://example.test/c.jpg',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = MovieApi(client: client);
    final details = await api.actorDetails(
      const MoviePerson(id: '10963', name: 'بازیگر'),
    );
    expect(details.bio, 'بازیگر آمریکایی');
    expect(details.titles.single.title, 'فیلم بازیگر');
    expect(
      await api.actorTitles(const MoviePerson(id: '10963', name: 'بازیگر')),
      hasLength(1),
    );
  });

  test('search queries the filter endpoint once per page', () async {
    var filterCalls = 0;
    final client = MockClient((request) async {
      final action = request.url.queryParameters['action']!;
      if (action == 'login') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'infos': [
                {'auth': 'sample'},
              ],
              'q1': 1,
              'q2': 2,
              'night_mode': '',
              'tx_size': '1',
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (action.startsWith('filter_search')) {
        filterCalls++;
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'all': [
                {
                  'videos_id': '9',
                  'title': 'یوفو',
                  'year': '2024',
                  'thumbnail_url': 'http://example.test/u.jpg',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = MovieApi(client: client, indexLoader: () async => '[]');
    final found = await api.search('یوفو');
    expect(found.single.title, 'یوفو');
    expect(filterCalls, 1);
  });

  test('text search falls back to scanning the browsable catalog', () async {
    final client = MockClient((request) async {
      final action = request.url.queryParameters['action']!;
      if (action == 'login') {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'infos': [
                {'auth': 'sample'},
              ],
              'q1': 1,
              'q2': 2,
              'night_mode': '',
              'tx_size': '1',
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (action.startsWith('filter_search')) {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'state_all': 'T', 'all': []})),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (action.startsWith('movie_list')) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'all': [
                {
                  'videos_id': '21',
                  'title': 'یوفو: راز آسمان',
                  'year': '2024',
                  'thumbnail_url': 'http://example.test/ufo.jpg',
                },
                {
                  'videos_id': '22',
                  'title': 'فیلم نامرتبط',
                  'year': '2023',
                  'thumbnail_url': 'http://example.test/other.jpg',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('{}', 404);
    });
    final api = MovieApi(client: client, indexLoader: () async => '[]');
    final found = await api.search('یوفو');
    expect(found.map((item) => item.title), ['یوفو: راز آسمان']);
  });

  test('genre opens titles when the upstream filter returns empty', () async {
    final client = MockClient((request) async {
      final action = request.url.queryParameters['action']!;
      if (action == 'login') {
        return http.Response(
          jsonEncode({
            'infos': [
              {'auth': 'sample'},
            ],
            'q1': 1,
            'q2': 2,
            'night_mode': '',
            'tx_size': '1',
          }),
          200,
        );
      }
      if (action.startsWith('filter_search')) {
        return http.Response(jsonEncode({'state_all': 'T', 'all': []}), 200);
      }
      if (action.startsWith('movie_list')) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'all': [
                {'videos_id': '21', 'title': 'فیلم درام'},
                {'videos_id': '22', 'title': 'فیلم کمدی'},
              ],
            }),
          ),
          200,
        );
      }
      if (action == 'detials') {
        final id = request.bodyFields['id'];
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'state_all': 'T',
              'detiles': [
                {'id': id, 'genre': id == '21' ? 'درام' : 'کمدی'},
              ],
            }),
          ),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    final api = MovieApi(client: client, indexLoader: () async => '[]');
    final items = await api.catalogByGroup(
      group: const CatalogGroup(id: '3', name: 'درام'),
      country: false,
    );
    expect(items.map((item) => item.id), ['21']);
  });
}
