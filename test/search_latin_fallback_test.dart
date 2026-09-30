import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/services/movie_api.dart';

/// The upstream `filter_search` endpoint only matches Persian text, so a
/// Latin query for a title missing from the bundled index (like "the perks")
/// must be resolved through the live detail "نام اصلی" fallback.
void main() {
  /// NOTE: Persian bodies must go through utf8 bytes — plain
  /// `http.Response(String)` encodes latin-1 and breaks the JSON.
  http.Response jsonBody(Map<String, Object?> json) =>
      http.Response.bytes(utf8.encode(jsonEncode(json)), 200);

  MovieApi api() {
    return MovieApi(
      client: MockClient((request) async {
        final action = request.url.queryParameters['action'] ?? '';
        if (action == 'login') {
          return jsonBody({
            'infos': [
              {'auth': 'guest'},
            ],
            'q1': 1,
            'q2': 2,
          });
        }
        if (action == 'movie_list') {
          final isMovie = request.bodyFields['is_movie'] == 'movie';
          final page = request.url.queryParameters['pageno'] ?? '1';
          if (isMovie && page == '1') {
            return jsonBody({
              'state_all': 'T',
              'all': [
                {
                  'videos_id': '99991',
                  'title': 'مزایای گوشه گیر بودن',
                  'thumbnail_url': 'http://example.com/p.jpg',
                  'year': '2012',
                  'imdb': '8.0',
                },
              ],
            });
          }
          return jsonBody({'state_all': 'T', 'all': []});
        }
        if (action == 'detials') {
          return jsonBody({
            'state_all': 'T',
            'detiles': [
              {
                // Real server shape: <br> separators and "خلاصه داستان"
                // WITHOUT a colon — the parser must still find نام اصلی.
                'description':
                    'نام اصلی : The Perks of Being a Wallflower<br>ژانر : درام , عاشقانه<br>خلاصه داستان<br>داستان چارلی.',
              },
            ],
          });
        }
        return jsonBody({'state_all': 'T', 'all': []});
      }),
      // Empty offline index so only the live fallbacks can match.
      indexLoader: () async => '[]',
    );
  }

  test(
    'latin query finds a Persian-only catalog title via original title',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final found = await api().search('the perks');
      expect(found.map((item) => item.id), contains('99991'));
    },
  );

  test('latin matching is case-insensitive', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final found = await api().search('THE PERKS');
    expect(found.map((item) => item.id), contains('99991'));
  });

  test('persian title scan still matches directly', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final found = await api().search('گوشه گیر');
    expect(found.map((item) => item.id), contains('99991'));
  });

  test(
    'bundled index carries the perks original title (regression data)',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final catalog = await rootBundle.loadString(
        'assets/catalog_index.json',
      );
      expect(catalog, contains('The Perks of Being a Wallflower'));
    },
  );
}
