import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mbnmovie/services/movie_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'partial English titles include canonical titles without aliases and rank relevant results',
    () async {
      final api = MovieApi(
        client: MockClient(
          (_) async => throw StateError('No network required'),
        ),
      );
      for (final query in [
        'house of',
        'HOUSE OF',
        'house   of',
        'house dragon',
        'خاندان',
      ]) {
        final results = await api.search(query);
        expect(results.map((e) => e.id), contains('11640'), reason: query);
      }
    },
  );
  test(
    'canonical title absent from aliases supports partial and exact filters',
    () async {
      final api = MovieApi(
        client: MockClient(
          (_) async => throw StateError('No network required'),
        ),
        indexLoader: () async => jsonEncode([
          {
            'id': '1',
            'title': 'خاندان اژدها',
            'english_title': 'House of the Dragon',
            'aliases': [],
            'kind': 'serie',
            'rating': '8.4',
          },
          for (var i = 2; i < 40; i++)
            {
              'id': '$i',
              'title': 'Other $i',
              'english_title': 'The House of Something $i',
              'aliases': [],
              'kind': 'movie',
              'rating': '4',
            },
        ]),
      );
      expect((await api.search('house of')).first.id, '1');
      expect((await api.search('dragon house')).map((e) => e.id), ['1']);
      expect(await api.advancedFilter(query: 'house of', exact: true), isEmpty);
      expect(
        (await api.advancedFilter(
          query: 'House of the Dragon',
          exact: true,
        )).map((e) => e.id),
        ['1'],
      );
    },
  );
}
