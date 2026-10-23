import 'dart:convert';

import 'package:http/http.dart' as http;

const offlineMovieId = '900001';
const offlineSeriesId = '900002';

Map<String, dynamic> catalogCard(String id) => {
  'id': id,
  'videos_id': id,
  'title': id == offlineMovieId ? 'Fresh Movie' : 'Fresh Series',
  'is_movie': id == offlineMovieId ? '1' : '0',
};

Map<String, dynamic> catalogReply(
  String action,
  Map<String, String> fields, {
  int episodeCount = 2,
}) {
  if (action == 'login') {
    return {
      'infos': [
        {'auth': 'single-use-guest', 'token': 'guest-token', 'login': 'T'},
      ],
      'q1': 1,
      'q2': 2,
    };
  }
  if (action == 'search_cast') {
    // The live actor search uses movie_list for people, not casts/all.
    return {
      'state_all': 'T',
      'movie_list': [
        {'id': '3', 'name': 'Test Actor'},
      ],
    };
  }
  final movie = catalogCard(offlineMovieId);
  final series = catalogCard(offlineSeriesId);
  return {
    'state_all': 'T',
    if (action == 'vitrin') ...{
      'NewMovie': [movie],
      'NewSerie': [series],
      'updated_serie': [series],
      'vige': [movie],
      'Nostalgy': [movie],
      'casts': [
        {'id': '3', 'name': 'Test Actor'},
      ],
      'Collection': [
        {'id': '4', 'title': 'Test Collection'},
      ],
      'mazamin': [
        {'id': '5', 'title': 'Test Tag'},
      ],
    },
    'genre': [
      {'genre_id': '6', 'name': 'Drama'},
    ],
    'country': [
      {'country_id': '7', 'name': 'Canada'},
    ],
    'all': [fields['is_movie'] == 'serie' ? series : movie],
    'list': action == 'collection_list'
        ? [
            {'id': '4', 'title': 'Test Collection'},
          ]
        : [movie],
    'casts': [
      {'id': '3', 'name': 'Test Actor'},
    ],
    'movie_list': [movie],
    'bio': 'Actor biography',
    'comments': [
      {'id': '8', 'name': 'Viewer', 'des': 'Test comment'},
    ],
    if (action == 'detials')
      'detiles': [
        {
          ...catalogCard(fields['id']!),
          'genre': 'Drama',
          'country': 'Canada',
          'download_link': fields['id'] == offlineMovieId
              ? [
                  {
                    'id': '720',
                    'name': '720p',
                    'link': 'https://cdn.example/movie.mp4',
                  },
                ]
              : [
                  {
                    'session_title': 'Season 1 720p',
                    'links': List.generate(
                      episodeCount,
                      (index) => {
                        'id': '${index + 1}',
                        'name': '${index + 1}',
                        'link': 'https://cdn.example/episode-${index + 1}.mp4',
                      },
                    ),
                  },
                ],
        },
      ],
  };
}

http.Response catalogResponse(http.Request request, {int episodeCount = 2}) =>
    http.Response.bytes(
      utf8.encode(
        jsonEncode(
          catalogReply(
            request.url.queryParameters['action']!,
            request.bodyFields,
            episodeCount: episodeCount,
          ),
        ),
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
