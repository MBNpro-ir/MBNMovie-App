import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/services/movie_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('search finds Breaking Bad in both English and Persian', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode({'all': [], 'state_all': 'T'}), 200);
    });

    final api = MovieApi(client: client);
    final englishResults = await api.search('breaking');
    expect(englishResults, isNotEmpty);
    expect(
      englishResults.any((m) => m.id == '8836' || m.alternateTitles.contains('Breaking Bad')),
      isTrue,
    );

    final persianResults = await api.search('افسار گسیخته');
    expect(persianResults, isNotEmpty);
    expect(persianResults.any((m) => m.id == '8836'), isTrue);
  });

  test('search retries on empty upstream responses up to maxAttempts', () async {
    var filterCalls = 0;
    final client = MockClient((request) async {
      if (request.url.queryParameters['action'] == 'login') {
        return http.Response(
          jsonEncode({
            'state_all': 'T',
            'infos': [{'auth': 'test_auth'}],
            'q1': 10,
            'q2': 20,
            'night_mode': '0',
            'tx_size': '1',
          }),
          200,
        );
      }
      final action = request.url.queryParameters['action'] ?? '';
      if (action.startsWith('filter_search')) {
        filterCalls++;
        if (filterCalls < 3) {
          return http.Response(jsonEncode({'all': [], 'state_all': 'T'}), 200);
        }
        return http.Response(
          jsonEncode({
            'state_all': 'T',
            'all': [
              {
                'videos_id': '99999',
                'title': 'Test Movie',
                'type': 'movie',
                'year': '2024',
                'imdb': '8.5',
              }
            ],
          }),
          200,
        );
      }
      return http.Response('{"state_all":"T"}', 200);
    });

    final api = MovieApi(client: client, indexLoader: () async => '[]');
    final results = await api.search('unique_query');
    expect(filterCalls, equals(3));
    expect(results, hasLength(1));
    expect(results.first.id, equals('99999'));
  });
}
