import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import '../core/title_language.dart';
import '../models/movie_content.dart';

class MovieApiException implements Exception {
  const MovieApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HomeCatalog {
  const HomeCatalog({
    required this.featured,
    required this.movies,
    required this.series,
    required this.sections,
    this.actors = const [],
    this.collections = const [],
    this.banners = const [],
    this.tags = const [],
    this.genres = const [],
    this.countries = const [],
  });
  final List<MovieContent> featured, movies, series;
  final List<HomeSection> sections;
  final List<MoviePerson> actors;
  final List<MovieCollection> collections;
  final List<MovieBanner> banners;
  final List<MovieTag> tags;
  final List<CatalogGroup> genres;
  final List<CatalogGroup> countries;
}

class HomeSection {
  const HomeSection({
    required this.id,
    required this.title,
    required this.items,
  });
  final String id, title;
  final List<MovieContent> items;
}

class CatalogGroup {
  const CatalogGroup({required this.id, required this.name, this.imageUrl});
  final String id, name;
  final String? imageUrl;
}

class MovieCollection {
  const MovieCollection({required this.id, required this.title, this.imageUrl});
  final String id, title;
  final String? imageUrl;
}

class MovieBanner {
  const MovieBanner({
    required this.imageUrl,
    required this.category,
    required this.title,
  });
  final String imageUrl, category, title;
}

class MovieTag {
  const MovieTag({required this.id, required this.title});
  final String id, title;
}

/// Guest authentication data for one catalog action.
class _AuthInit {
  const _AuthInit({
    required this.auth,
    required this.q1,
    required this.q2,
    required this.night,
    required this.tx,
    required this.mobile,
    required this.token,
  });
  final String auth, night, tx, mobile, token;
  final int q1, q2;
}

abstract interface class ContentApi {
  Future<MovieContent> details(MovieContent summary);
  Future<List<MovieComment>> comments(String contentId);
}

/// Connects the existing MBNMovie interface to the film catalog service.
class MovieApi implements ContentApi {
  MovieApi({http.Client? client, Future<String> Function()? indexLoader})
    : _client = client ?? http.Client(),
      _indexLoader = indexLoader ?? _loadBundledIndex;

  static Future<String> _loadBundledIndex() =>
      rootBundle.loadString('assets/catalog_index.json');
  final Future<String> Function() _indexLoader;
  String _delfanMobile = '';
  String _delfanPassword = '';

  void bindDelfanSession({required String mobile, required String password}) {
    _delfanMobile = mobile;
    _delfanPassword = password;
    _homeData = null;
    _catalogPageCache.clear();
  }

  void clearDelfanSession() => bindDelfanSession(mobile: '', password: '');
  Future<List<Map<String, dynamic>>>? _indexFuture;

  Future<List<Map<String, dynamic>>> _index() => _indexFuture ??= () async {
    try {
      return _list(jsonDecode(await _indexLoader())).map(_map).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }();

  MovieContent _indexItem(Map<String, dynamic> row) {
    final kind = _text(row['kind']) == 'serie'
        ? ContentKind.series
        : ContentKind.movie;
    final image = _text(row['image']);
    List<String> parts(Object? raw) => _text(raw)
        .split(RegExp(r'[,،]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    return MovieContent(
      id: _text(row['id']),
      title: _text(row['title']),
      subtitle: kind == ContentKind.series ? 'سریال' : 'فیلم',
      description: '',
      year: int.tryParse(_text(row['year'])) ?? 0,
      rating: double.tryParse(_text(row['rating'])) ?? 0,
      kind: kind,
      colors: const [Color(0xFF4665B3), Color(0xFF10182B)],
      genres: parts(row['genres']),
      countries: parts(row['countries']),
      alternateTitles: _list(row['aliases']).map(_text).toList(),
      imageUrl: image.isEmpty ? null : image,
      backdropUrl: image.isEmpty ? null : image,
      isDubbed: _text(row['is_duble']).toUpperCase() == 'T',
    );
  }

  Future<List<MovieContent>> _indexFilter({
    String query = '',
    bool exact = false,
    String type = '',
    String dub = '',
    String genre = '',
    String country = '',
    String imdb = '',
    String sortBy = 'NewMovie',
    String yearFrom = '',
    String yearTo = '',
    String stateSerie = '',
    int page = 1,
    List<MovieContent>? source,
  }) async {
    final indexRows = await _index();
    final sourceById = source == null
        ? null
        : {for (final item in source) item.id: item};
    final rows = sourceById == null
        ? indexRows
        : indexRows
              .where((row) => sourceById.containsKey(_text(row['id'])))
              .toList();
    if (sourceById != null) {
      final indexedIds = {for (final row in rows) _text(row['id'])};
      for (final item in sourceById.values) {
        if (indexedIds.contains(item.id)) continue;
        try {
          final data = await _detailData(item.id);
          final detail = _map(_list(data['detiles']).firstOrNull);
          rows.add({
            'id': item.id,
            'title': item.title,
            'image': item.imageUrl ?? '',
            'year': _text(detail['year']).isEmpty
                ? '${item.year}'
                : detail['year'],
            'rating': _text(detail['imdb_rating']).isEmpty
                ? '${item.rating}'
                : detail['imdb_rating'],
            'kind': item.kind == ContentKind.series ? 'serie' : 'movie',
            'aliases': [
              ...item.alternateTitles,
              if (_splitBiography(_plainDescription(detail['description'])).$2
                  case final String title)
                title,
            ],
            'genres': detail['genre'] ?? '',
            'countries': detail['country'] ?? '',
            'is_duble': detail['is_duble'] ?? '',
            'subtitles': detail['subtitles'] ?? '',
            'state_serie': detail['state_serie'] ?? '',
          });
        } catch (_) {
          // A new item can still match by its visible title and basic fields.
          rows.add({
            'id': item.id,
            'title': item.title,
            'image': item.imageUrl ?? '',
            'year': '${item.year}',
            'rating': '${item.rating}',
            'kind': item.kind == ContentKind.series ? 'serie' : 'movie',
            'aliases': item.alternateTitles,
            'genres': item.genres.join(','),
            'countries': item.countries.join(','),
          });
        }
      }
      final needsOriginalTitle = RegExp(r'[A-Za-z]').hasMatch(query);
      for (final row in rows) {
        final missingMetadata =
            (needsOriginalTitle && _list(row['aliases']).isEmpty) ||
            (genre.isNotEmpty && _text(row['genres']).isEmpty) ||
            (country.isNotEmpty && _text(row['countries']).isEmpty) ||
            (dub.isNotEmpty && !row.containsKey('is_duble')) ||
            (stateSerie.isNotEmpty && !row.containsKey('state_serie'));
        if (!missingMetadata) continue;
        try {
          final detailData = await _detailData(_text(row['id']));
          final detail = _map(_list(detailData['detiles']).firstOrNull);
          row['aliases'] = [
            ..._list(row['aliases']),
            if (_splitBiography(_plainDescription(detail['description'])).$2
                case final String title)
              title,
          ];
          row['genres'] = detail['genre'] ?? row['genres'] ?? '';
          row['countries'] = detail['country'] ?? row['countries'] ?? '';
          row['is_duble'] = detail['is_duble'] ?? '';
          row['subtitles'] = detail['subtitles'] ?? '';
          row['state_serie'] = detail['state_serie'] ?? '';
        } catch (_) {}
      }
    }
    if (rows.isEmpty) return const [];
    final groups = genre.isNotEmpty || country.isNotEmpty
        ? await Future.wait([genres(), countries()])
        : <List<CatalogGroup>>[const [], const []];
    String groupName(List<CatalogGroup> options, String id) {
      if (id.isEmpty) return '';
      for (final group in options) {
        if (group.id == id) return _normalizeQuery(group.name);
      }
      return _normalizeQuery(id);
    }

    final genreName = groupName(groups[0], genre);
    final countryName = groupName(groups[1], country);
    final needle = _normalizeQuery(query);
    final minimum = double.tryParse(imdb);
    final fromYear = int.tryParse(yearFrom);
    final toYear = int.tryParse(yearTo);
    final matches = <MovieContent>[];
    for (final row in rows) {
      final item = _indexItem(row);
      if (item.id.isEmpty || isPromotionalContent(item)) continue;
      if (type.isNotEmpty &&
          item.kind !=
              (type == 'serie' ? ContentKind.series : ContentKind.movie)) {
        continue;
      }
      if (needle.isNotEmpty) {
        final names = [
          item.title,
          ...item.alternateTitles,
        ].map(_normalizeQuery);
        if (!names.any(
          (name) => exact ? name == needle : name.contains(needle),
        )) {
          continue;
        }
      }
      if (genreName.isNotEmpty &&
          !item.genres.map(_normalizeQuery).contains(genreName)) {
        continue;
      }
      if (countryName.isNotEmpty &&
          !item.countries.map(_normalizeQuery).contains(countryName)) {
        continue;
      }
      if (minimum != null && item.rating < minimum) continue;
      if (fromYear != null && item.year < fromYear) continue;
      if (toYear != null && item.year > toYear) continue;
      final dubbed = _text(row['is_duble']).toUpperCase();
      final subtitle = _text(row['subtitles']);
      if (dub == 'dub' && dubbed != 'T') continue;
      if (dub == 'sub' && subtitle.isEmpty) continue;
      if (dub == 'nosub' && (dubbed == 'T' || subtitle.isNotEmpty)) continue;
      if (stateSerie.isNotEmpty && _text(row['state_serie']) != stateSerie) {
        continue;
      }
      matches.add(item);
    }
    if (sortBy == 'imdb') {
      matches.sort((a, b) => b.rating.compareTo(a.rating));
    } else if (sortBy == 'new' || sortBy == 'NewMovie') {
      matches.sort(
        (a, b) => (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0),
      );
    }
    return matches.skip((page - 1) * 24).take(24).toList();
  }

  Future<List<MovieContent>> filterWithinSource(
    List<MovieContent> source, {
    String query = '',
    bool exact = false,
    String type = '',
    String dub = '',
    String genre = '',
    String country = '',
    String imdb = '',
    String sortBy = 'NewMovie',
    String yearFrom = '',
    String yearTo = '',
    String stateSerie = '',
    int page = 1,
  }) => _indexFilter(
    source: source,
    query: query,
    exact: exact,
    type: type,
    dub: dub,
    genre: genre,
    country: country,
    imdb: imdb,
    sortBy: sortBy,
    yearFrom: yearFrom,
    yearTo: yearTo,
    stateSerie: stateSerie,
    page: page,
  );

  // The original account screens and storage remain available for a future
  // account adapter. Guest access is the active path for this version.
  String? get sessionCookie => null;
  void restoreCookie(String cookie) {}
  void clearSession() {}
  Future<bool> validateCurrentSession() async => false;
  Future<bool> login({required String email, required String password}) async =>
      false;
  Future<bool> register({
    required String name,
    required String email,
    required String mobile,
    required String password,
  }) async => false;

  static const _base = 'http://googfilmazappfordownfilmmedis.xyz/app-plus/';
  // Release builds inject the service key via --dart-define MBN_API_KEY
  // (GitHub secret); local/debug builds fall back to the audited key.
  static const _key = String.fromEnvironment(
    'MBN_API_KEY',
    defaultValue: 'pwep5d4sdoe0ewsosa7d563d',
  );
  static const _wireApp = 'Delfan';
  static const _headers = {'User-Agent': 'Mozilla/5.0 (Linux; Android 15)'};
  final http.Client _client;
  Future<void> _tail = Future<void>.value();
  Map<String, dynamic>? _homeData;
  final Map<String, List<MovieContent>> _catalogPageCache = {};
  final Map<String, ({List<String> genres, List<String> countries})>
  _groupDetailCache = {};

  static String _text(Object? value) => value?.toString().trim() ?? '';
  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? value.map((key, value) => MapEntry('$key', value)) : {};
  static List<dynamic> _list(Object? value) {
    if (value is List) return value;
    if (value is String) {
      try {
        return _list(jsonDecode(value));
      } catch (_) {}
    }
    return [];
  }

  static String _md5(String value) =>
      md5.convert(utf8.encode(value)).toString();
  static String _plainDescription(Object? value) =>
      html
          .parse(
            _text(
              value,
            ).replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n'),
          )
          .body
          ?.text
          .replaceAll('\r', '\n')
          .replaceAll(RegExp(r'[ \t]+'), ' ')
          .replaceAll(RegExp(r'\n\s*\n+'), '\n')
          .trim() ??
      '';
  static bool _adult(String value) => RegExp(
    r'(^|\W)(18\+|\+18|adult|hentai|porn|xxx)(\W|$)|بزرگسال|هنتای|پورن',
    caseSensitive: false,
  ).hasMatch(value);
  static bool isPromotionalContent(MovieContent content) =>
      _adult(content.title) || _adult(content.description);

  Future<Map<String, dynamic>> _request(
    String action, [
    Map<String, String> extra = const {},
  ]) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          return await _send(action, extra);
        } on FormatException catch (e) {
          lastError = e;
        } on TimeoutException catch (e) {
          lastError = e;
        } catch (e) {
          lastError = e;
        }
        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 400 * (attempt + 1)),
          );
        }
      }
      if (lastError is FormatException) throw lastError;
      throw const FormatException('پاسخ نامعتبر');
    } finally {
      done.complete();
    }
  }

  Future<_AuthInit> _loginInit() async {
    // The catalog service consumes the guest auth for one vp1 request.
    // Reusing it makes every subsequent action fail with state_all=F.
    final login = await _client
        .post(
          Uri.parse('${_base}users.php?key=$_key&action=login'),
          headers: _headers,
          body: {
            'user_name': _delfanMobile,
            if (_delfanMobile.isNotEmpty) 'pass': _delfanPassword,
            'token': '',
            'android_id': '',
            'app_verion': '2',
            'version_sp': 'ورژن 2',
            'is_tv': '',
            'apname': _delfanMobile.isEmpty ? _wireApp : 'Delfan',
          },
        )
        .timeout(const Duration(seconds: 20));
    final init = _map(jsonDecode(utf8.decode(login.bodyBytes)));
    final info = _map(_list(init['infos']).firstOrNull);
    if (_delfanMobile.isNotEmpty && _text(info['login']) != 'T') {
      throw FormatException(_text(info['msg']).isEmpty
          ? 'اتصال حساب برقرار نشد' : _text(info['msg']));
    }
    final auth = _text(info['auth']);
    if (auth.isEmpty) throw const FormatException('نشست مهمان معتبر نیست');
    final parsed = _AuthInit(
      auth: auth,
      q1: int.tryParse(_text(init['q1'])) ?? 0,
      q2: int.tryParse(_text(init['q2'])) ?? 0,
      night: _text(init['night_mode']),
      tx: _text(init['tx_size']),
      mobile: _delfanMobile,
      token: _text(info['token']),
    );
    return parsed;
  }

  Future<Map<String, dynamic>> _send(
    String action,
    Map<String, String> extra,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final init = await _loginInit();
      final nonce = DateTime.now().microsecondsSinceEpoch % 500;
      final body =
          '${_md5('${nonce}cotation')}${init.auth}'
          'fdaa94a151e2c5d474a290e8${init.auth}y87mdjsodon'
          'c215sfxd545fgs${_md5('${DateTime.now().toUtc()}cotation')}';
      final response = await _client
          .post(
            Uri.parse('${_base}vp1.php?key=$_key&action=$action'),
            headers: _headers,
            body: {
              'user_name': init.mobile,
              'token': init.token,
              'body': body,
              'an': _md5('${init.q1 + init.q2 + 101}'),
              'langueg': '',
              'u_s': init.night,
              's_n': init.tx,
              'apname': init.mobile.isEmpty ? _wireApp : 'Delfan',
              ...extra,
            },
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        throw const FormatException('سرور پاسخ نداد');
      }
      final result = _map(jsonDecode(utf8.decode(response.bodyBytes)));
      if (_text(result['state_all']) == 'F') {
        // A guest auth can expire before use; retry once with a fresh login.
        if (attempt == 0) continue;
        final message = _text(result['msg']);
        throw FormatException(message.isEmpty ? 'سرور پاسخ نداد' : message);
      }
      return result;
    }
    throw const FormatException('سرور پاسخ نداد');
  }

  ContentKind _kind(Map<String, dynamic> row, ContentKind hint) {
    final value = _text(row['is_movie'] ?? row['type']).toLowerCase();
    if (value == '0' || value == 'serie' || value == 'series' || value == '2') {
      return ContentKind.series;
    }
    if (value == '1' || value == 'movie' || value == 'movies') {
      return ContentKind.movie;
    }
    return hint;
  }

  MovieContent _item(Map<String, dynamic> row, ContentKind hint) {
    final kind = _kind(row, hint);
    final image = _text(row['thumbnail_url'] ?? row['poster_url']);
    return MovieContent(
      id: _text(row['videos_id'] ?? row['id']),
      title: _text(row['title']),
      subtitle: kind == ContentKind.series ? 'سریال' : 'فیلم',
      description: '',
      year: int.tryParse(_text(row['year'])) ?? 0,
      rating: double.tryParse(_text(row['imdb'] ?? row['imdb_rating'])) ?? 0,
      kind: kind,
      colors: const [Color(0xFF4665B3), Color(0xFF10182B)],
      genres: const [],
      imageUrl: image.isEmpty ? null : image,
      backdropUrl: image.isEmpty ? null : image,
    );
  }

  List<MovieContent> _items(Object? rows, ContentKind hint) => _list(rows)
      .map((row) => _item(_map(row), hint))
      .where(
        (item) =>
            item.id.isNotEmpty &&
            item.title.isNotEmpty &&
            !isPromotionalContent(item),
      )
      .toList();
  Future<Map<String, dynamic>> _home() async =>
      _homeData ??= await _request('vitrin');

  List<MoviePerson> _people(Object? rows) => _list(rows)
      .map(_map)
      .map(
        (row) => MoviePerson(
          id: _text(row['id'] ?? row['cast_id']),
          name: _text(row['name']),
          imageUrl: _text(row['pic_url']),
          role: _text(row['action_user']),
        ),
      )
      .where(
        (person) =>
            person.id.isNotEmpty &&
            person.name.isNotEmpty &&
            !_adult(person.name),
      )
      .toList();

  /// تلاش‌های مجدد با نشست تازه وقتی پاسخ خالی برگردد تا از بازگشت
  /// لیست خالی به کاربر جلوگیری شود.
  Future<List<T>> _firstPageWithRetry<T>(
    Future<List<T>> Function() fetch, {
    int maxAttempts = 3,
  }) async {
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final result = await fetch();
        if (result.isNotEmpty) return result;
      } catch (_) {
        if (attempt == maxAttempts - 1) rethrow;
      }
      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
    return <T>[];
  }

  List<MovieCollection> _collections(Object? rows) => _list(rows)
      .map(_map)
      .map(
        (row) => MovieCollection(
          id: _text(row['id']),
          title: _text(row['title']),
          imageUrl: _text(row['thumbnail_url']).isEmpty
              ? null
              : _text(row['thumbnail_url']),
        ),
      )
      .where((c) => c.id.isNotEmpty && c.title.isNotEmpty && !_adult(c.title))
      .toList();

  List<MovieBanner> _banners(Object? rows) {
    final out = <MovieBanner>[];
    for (final row in _list(rows).map(_map)) {
      for (var i = 1; i <= 3; i++) {
        final pic = _text(row['pic$i']);
        final cat = _text(row['cat$i']);
        final title = _text(row['title$i']);
        if (pic.isEmpty || cat.isEmpty) continue;
        if (_adult('$title $cat')) continue;
        out.add(
          MovieBanner(
            imageUrl: pic,
            category: cat,
            title: title.isEmpty ? cat : title,
          ),
        );
      }
    }
    return out;
  }

  List<MovieTag> _tags(Object? rows) => _list(rows)
      .map(_map)
      .map((row) => MovieTag(id: _text(row['id']), title: _text(row['title'])))
      .where(
        (tag) =>
            tag.id.isNotEmpty && tag.title.isNotEmpty && !_adult(tag.title),
      )
      .toList();

  Future<HomeCatalog> home() async {
    try {
      _homeData = null;
      final data = await _home();
      final movies = _items(data['NewMovie'], ContentKind.movie);
      final series = _items(data['NewSerie'], ContentKind.series);
      return HomeCatalog(
        featured: [...movies, ...series].take(8).toList(),
        movies: movies,
        series: series,
        actors: _people(data['casts']),
        collections: _collections(data['Collection']),
        banners: _banners(data['banner_cnt']),
        tags: _tags(data['mazamin']),
        genres: _groups(data['genre'], 'genre_id'),
        countries: _groups(data['country'], 'country_id'),
        sections: [
          HomeSection(
            id: 'updated',
            title: 'سریال‌های به‌روزشده',
            items: _items(data['updated_serie'], ContentKind.series),
          ),
          HomeSection(
            id: 'featured',
            title: 'پیشنهاد ویژه',
            items: _items(data['vige'], ContentKind.movie),
          ),
          HomeSection(
            id: 'classic',
            title: 'نوستالژی',
            items: _items(data['Nostalgy'], ContentKind.movie),
          ),
        ].where((section) => section.items.isNotEmpty).toList(),
      );
    } catch (_) {
      throw const MovieApiException('کاتالوگ MBNMovie قابل خواندن نیست.');
    }
  }

  Future<List<MovieContent>> catalog({
    required ContentKind kind,
    int page = 1,
  }) async {
    try {
      Future<List<MovieContent>> fetch() async {
        final data = await _request('movie_list&pageno=$page', {
          'c': '2',
          'select_dub': '',
          'is_movie': kind == ContentKind.series ? 'serie' : 'movie',
        });
        return _items(data['all'], kind);
      }

      if (page > 1) return await fetch();
      return await _firstPageWithRetry(fetch);
    } catch (_) {
      throw const MovieApiException('فهرست محتوا قابل خواندن نیست.');
    }
  }

  Future<List<MovieCollection>> collections({int page = 1}) async {
    try {
      Future<List<MovieCollection>> fetch() async {
        final data = await _request('collection_list&pageno=$page');
        final rows = data['list'] ?? data['all'] ?? data['collection'];
        return _collections(rows);
      }

      if (page > 1) return await fetch();
      return await _firstPageWithRetry(fetch, maxAttempts: 3);
    } catch (_) {
      return const [];
    }
  }

  Future<List<MovieContent>> collectionTitles(
    MovieCollection collection, {
    int page = 1,
  }) async {
    try {
      Future<List<MovieContent>> fetch() async {
        final data = await _request('collection_show&pageno=$page', {
          'video_id': collection.id,
        });
        final rows = data['list'] ??
            data['all'] ??
            data['movie_list'] ??
            data['collection'];
        return _items(rows, ContentKind.movie);
      }

      if (page > 1) return await fetch();
      return await _firstPageWithRetry(fetch);
    } catch (_) {
      throw const MovieApiException('آثار این مجموعه قابل خواندن نیست.');
    }
  }

  Future<List<MovieContent>> titlesByCategory(
    MovieBanner banner, {
    String isMovie = 'movie',
    int page = 1,
  }) async {
    try {
      Future<List<MovieContent>> fetch() async {
        final data = await _request('movie_list_country&pageno=$page', {
          'c': banner.category,
          'select_dub': '',
          'is_movie': isMovie,
        });
        return _items(data['all'], ContentKind.movie);
      }

      if (page > 1) return await fetch();
      return await _firstPageWithRetry(fetch);
    } catch (_) {
      throw const MovieApiException('محتوای این بخش قابل خواندن نیست.');
    }
  }

  Future<List<MovieTag>> tags() async {
    try {
      final data = await _home();
      final cached = _tags(data['mazamin']);
      if (cached.isNotEmpty) return cached;
      final fresh = await _request('mazamin');
      return _tags(fresh['mazamin'] ?? fresh['all']);
    } catch (_) {
      throw const MovieApiException('برچسب‌ها قابل خواندن نیست.');
    }
  }

  Future<List<CatalogGroup>> filterOptions({required bool country}) async {
    try {
      final data = await _request('Filter_Option');
      final result = country
          ? _groups(data['country'], 'country_id')
          : _groups(data['genre'], 'genre_id');
      if (result.isNotEmpty) return result;
    } catch (_) {}
    // The endpoint can return a successful but empty response for guest users.
    return country ? countries() : genres();
  }

  List<CatalogGroup> _groups(Object? rows, String key) => _list(rows)
      .map(_map)
      .map(
        (row) => CatalogGroup(
          id: _text(row[key]),
          name: _text(row['name']),
          imageUrl: _text(row['pic_url']),
        ),
      )
      .where(
        (group) =>
            group.id.isNotEmpty && group.name.isNotEmpty && !_adult(group.name),
      )
      .toList();
  Future<List<CatalogGroup>> genres() async =>
      _groups((await _home())['genre'], 'genre_id');
  Future<List<CatalogGroup>> countries() async =>
      _groups((await _home())['country'], 'country_id');
  Future<List<CatalogGroup>> countriesWithContent() => countries();
  Future<List<MoviePerson>> actors({int page = 1}) async {
    if (page <= 1) {
      final featured = _people((await _home())['casts']);
      if (featured.isNotEmpty) return featured;
    }
    // صفحه اول همان بازیگران ویترین است؛ صفحه‌های بعدی از همان
    // ابتدای فهرست cast_list می‌آیند تا چیزی جا نماند.
    final castPage = page <= 1 ? 1 : page - 1;
    try {
      final data = await _request('cast_list&pageno=$castPage', {
        'cast_type': 'cast',
      });
      return _people(
        data['casts'] ?? data['cast_list'] ?? data['movie_list'] ?? data['all'],
      );
    } catch (_) {
      throw const MovieApiException('فهرست بازیگران قابل خواندن نیست.');
    }
  }

  Future<List<MoviePerson>> searchActors(String query, {int page = 1}) async {
    if (query.trim().length < 2) return [];
    try {
      final data = await _request('search_cast&pageno=$page', {
        'q': query.trim(),
        'cast_type': 'cast',
      });
      return _people(data['casts'] ?? data['cast_list'] ?? data['all']);
    } catch (_) {
      throw const MovieApiException('جست‌وجوی بازیگران در دسترس نیست.');
    }
  }

  Future<List<MovieContent>> actorTitles(
    MoviePerson person, {
    int page = 1,
  }) async {
    final details = await actorDetails(person, page: page);
    return details.titles;
  }

  /// آثار یک بازیگر همراه بیوگرافی او (مطابق پاسخ show_movie_cast).
  Future<({List<MovieContent> titles, String bio})> actorDetails(
    MoviePerson person, {
    int page = 1,
  }) async {
    try {
      Future<({List<MovieContent> titles, String bio})> fetch() async {
        final data = await _request('show_movie_cast&pageno=$page', {
          'cast_id': person.id,
          'cast_type': 'cast',
        });
        final titles = _items(
          data['movie_list'] ?? data['all'] ?? data['casts'],
          ContentKind.movie,
        );
        final bio = _plainDescription(data['bio']);
        return (titles: titles, bio: bio);
      }

      final first = await fetch();
      if (first.titles.isNotEmpty || page > 1) return first;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return await fetch();
    } catch (_) {
      throw const MovieApiException('آثار این بازیگر قابل خواندن نیست.');
    }
  }

  Map<String, String> _searchFields({
    String query = '',
    String sortBy = 'NewMovie',
  }) => {
    'type': '',
    'dub': '',
    'genre': '',
    'country': '',
    'imdb': '',
    'sort_by': sortBy,
    'year_from': '',
    'year_to': '',
    'StateSerie': '',
    'search_text': query,
    'StateCheckSearchDagig': 'F',
    'langueg': '',
  };
  Future<List<MovieContent>> catalogByGroup({
    required CatalogGroup group,
    required bool country,
    int page = 1,
  }) async {
    try {
      Future<List<MovieContent>> fetch() async {
        final data = await _request('filter_search&pageno=$page', {
          ..._searchFields(),
          country ? 'country' : 'genre': group.id,
        });
        return _items(data['all'], ContentKind.movie);
      }

      final direct = page > 1
          ? await fetch()
          : await _firstPageWithRetry(fetch);
      if (direct.isNotEmpty) return direct;
    } catch (_) {}
    try {
      final indexed = await _indexFilter(
        genre: country ? '' : group.id,
        country: country ? group.id : '',
        page: page,
      );
      if (indexed.isNotEmpty) return indexed;
    } catch (_) {}
    try {
      return await _catalogScanGroup(group, country: country, page: page);
    } catch (_) {
      throw const MovieApiException('محتوای این دسته قابل خواندن نیست.');
    }
  }

  Future<List<MovieContent>> advancedFilter({
    String query = '',
    bool exact = false,
    String type = '',
    String dub = '',
    String genre = '',
    String country = '',
    String imdb = '',
    String sortBy = 'NewMovie',
    String yearFrom = '',
    String yearTo = '',
    String stateSerie = '',
    int page = 1,
  }) async {
    List<MovieContent> direct = const [];
    try {
      Future<List<MovieContent>> fetch() async {
        final data = await _request('filter_search&pageno=$page', {
          'type': type,
          'dub': dub,
          'genre': genre,
          'country': country,
          'imdb': imdb,
          'sort_by': sortBy,
          'year_from': yearFrom,
          'year_to': yearTo,
          'StateSerie': stateSerie,
          'search_text': query,
          'StateCheckSearchDagig': exact ? 'T' : 'F',
        });
        return _items(data['all'], ContentKind.movie);
      }

      direct = page > 1
          ? await fetch()
          : await _firstPageWithRetry(fetch);
      if (direct.isNotEmpty) return direct;
    } catch (_) {
      // An upstream error must still leave the bundled index available.
    }
    try {
      return await _indexFilter(
        query: query,
        exact: exact,
        type: type,
        dub: dub,
        genre: genre,
        country: country,
        imdb: imdb,
        sortBy: sortBy,
        yearFrom: yearFrom,
        yearTo: yearTo,
        stateSerie: stateSerie,
        page: page,
      );
    } catch (_) {
      throw const MovieApiException('فیلتر پیشرفته در دسترس نیست.');
    }
  }

  Future<List<MovieContent>> search(
    String query, {
    int page = 1,
    void Function(List<MovieContent>)? onPartial,
    bool Function()? isCanceled,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      Future<List<MovieContent>> fetch() async {
        return await _firstPageWithRetry(() async {
          final data = await _request(
            'filter_search&pageno=$page',
            _searchFields(query: trimmed),
          );
          return _items(data['all'], ContentKind.movie);
        }, maxAttempts: 3);
      }

      final fetchFuture = fetch().catchError((_) => <MovieContent>[]);
      final indexFuture =
          _indexFilter(query: trimmed, page: page).catchError((_) => <MovieContent>[]);

      final results = await Future.wait([fetchFuture, indexFuture]);
      final primary = results[0];
      final indexed = results[1];

      if (primary.isEmpty && indexed.isEmpty) {
        final scanned = await _catalogScanSearch(
          trimmed,
          page: page,
          onPartial: onPartial,
          isCanceled: isCanceled,
        );
        if (scanned.isNotEmpty) return scanned;
        // Upstream only matches Persian text, so a Latin query for a title
        // missing from the bundled index (e.g. "the perks") would otherwise
        // always come back empty. Last resort: compare live "نام اصلی".
        return await _latinOriginalTitleScan(
          trimmed,
          page: page,
          onPartial: onPartial,
          isCanceled: isCanceled,
        );
      }

      final combined = <MovieContent>[];
      final seen = <String>{};
      final needle = _normalizeQuery(trimmed);

      // 1. Prioritize strong matches from indexed (where title or aliases start with or contain needle)
      for (final item in indexed) {
        final names = [item.title, ...item.alternateTitles].map(_normalizeQuery);
        if (names.any((n) => n.startsWith(needle) || n == needle) && seen.add(item.id)) {
          combined.add(item);
        }
      }

      // 2. Add remaining indexed matches
      for (final item in indexed) {
        if (seen.add(item.id)) {
          combined.add(item);
        }
      }

      // 3. Add primary upstream results
      for (final item in primary) {
        if (seen.add(item.id)) {
          combined.add(item);
        }
      }

      return combined.take(24).toList();
    } catch (_) {
      // The upstream search endpoint can reject guest requests even while
      // movie_list remains available. Keep text search usable in that case.
      try {
        return await _catalogScanSearch(
          trimmed,
          page: page,
          onPartial: onPartial,
          isCanceled: isCanceled,
        );
      } catch (_) {
        throw const MovieApiException('جست‌وجوی آنلاین در دسترس نیست.');
      }
    }
  }

  Future<List<MovieContent>> _catalogPage(ContentKind kind, int page) async {
    final key = '${kind.name}:$page';
    final cached = _catalogPageCache[key];
    if (cached != null) return cached;
    final data = await _request('movie_list&pageno=$page', {
      'c': '2',
      'select_dub': '',
      'is_movie': kind == ContentKind.series ? 'serie' : 'movie',
    });
    final items = _items(data['all'], kind);
    _catalogPageCache[key] = items;
    return items;
  }

  Future<({List<String> genres, List<String> countries})?> _categoriesFor(
    MovieContent item,
  ) async {
    final cached = _groupDetailCache[item.id];
    if (cached != null) return cached;
    try {
      final data = await _send('detials', {'id': item.id, 'is_mobile': '1'});
      final row = _map(_list(data['detiles']).firstOrNull);
      if (row.isEmpty) return null;
      List<String> values(Object? raw) => _text(raw)
          .split(RegExp(r'[,،]'))
          .map((part) => _normalizeQuery(part))
          .where((part) => part.isNotEmpty)
          .toList();
      final categories = (
        genres: values(row['genre'] ?? row['genres']),
        countries: values(row['country'] ?? row['countries']),
      );
      _groupDetailCache[item.id] = categories;
      return categories;
    } catch (_) {
      return null;
    }
  }

  Future<List<MovieContent>> _catalogScanGroup(
    CatalogGroup group, {
    required bool country,
    required int page,
  }) async {
    final name = _normalizeQuery(group.name);
    final matches = <MovieContent>[];
    final seen = <String>{};
    final needed = page * 24;
    for (var catalogPage = 1; catalogPage <= 12; catalogPage++) {
      final candidates = <MovieContent>[
        ...await _catalogPage(ContentKind.movie, catalogPage),
        ...await _catalogPage(ContentKind.series, catalogPage),
      ];
      if (candidates.isEmpty) break;
      for (var offset = 0; offset < candidates.length; offset += 5) {
        final batch = candidates.skip(offset).take(5).toList();
        final categories = await Future.wait(batch.map(_categoriesFor));
        for (var index = 0; index < batch.length; index++) {
          final values = country
              ? categories[index]?.countries ?? const <String>[]
              : categories[index]?.genres ?? const <String>[];
          if (values.any((value) => value == name || value.contains(name)) &&
              seen.add(batch[index].id)) {
            matches.add(batch[index]);
          }
        }
        if (matches.length >= needed) break;
      }
      if (matches.length >= needed || candidates.length < 40) break;
    }
    return matches.skip((page - 1) * 24).take(24).toList();
  }

  /// یکدست‌سازی متن برای تطبیق عنوان‌ها (رسم‌الخط فارسی، نیم‌فاصله).
  static String _normalizeQuery(String value) => value
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'[آأإٱ]'), 'ا')
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670ـ]'), '')
      .replaceAll('‌', '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('بریکینگ', 'برکینگ')
      .toLowerCase();

  Future<List<MovieContent>> _catalogScanSearch(
    String query, {
    int page = 1,
    void Function(List<MovieContent>)? onPartial,
    bool Function()? isCanceled,
  }) async {
    final needle = _normalizeQuery(query);
    if (needle.length < 2) return const [];
    const pageSize = 24;
    const maxCatalogPages = 40;

    Future<List<MovieContent>> pageOf(ContentKind kind, int page) async {
      try {
        return await _catalogPage(kind, page);
      } catch (_) {
        return const <MovieContent>[];
      }
    }

    final matches = <MovieContent>[];
    void absorb(List<MovieContent> items) {
      for (final item in items) {
        // Catalog rows from the server carry Persian titles only, so a Latin
        // query (e.g. "the perks") must also match the offline English alias
        // from the bundled catalog index — otherwise English search silently
        // finds nothing even though the title exists.
        final original = TitleLanguage.originalTitleFor(item.id);
        final names = [
          item.title,
          ...item.alternateTitles,
          if (original != null && original.isNotEmpty) original,
        ].map(_normalizeQuery);
        if (names.any((name) => name.contains(needle)) &&
            !matches.any((old) => old.id == item.id)) {
          matches.add(item);
        }
      }
    }

    for (var catalogPage = 1; catalogPage <= maxCatalogPages; catalogPage++) {
      if (isCanceled?.call() ?? false) return const [];
      final pages = [
        await pageOf(ContentKind.movie, catalogPage),
        await pageOf(ContentKind.series, catalogPage),
      ];
      if (pages.every((items) => items.isEmpty)) break;
      for (final items in pages) {
        absorb(items);
      }
      if (matches.isNotEmpty) {
        onPartial?.call(matches.take(page * pageSize).toList());
      }
      if (matches.length >= page * pageSize) break;
      if (page == 1 && catalogPage >= 3 && matches.isNotEmpty) break;
    }
    final start = (page - 1) * pageSize;
    if (start >= matches.length) return const [];
    return matches.skip(start).take(pageSize).toList();
  }

  /// Last-resort Latin search. The upstream endpoint only matches Persian
  /// text and the bundled index can miss titles, so for a Latin query with
  /// zero matches we read live catalog pages and compare each item's detail
  /// "نام اصلی" (original title). Bounded (first pages only), batched,
  /// cancelable and partial-streaming — same pattern as _catalogScanGroup.
  Future<List<MovieContent>> _latinOriginalTitleScan(
    String query, {
    int page = 1,
    void Function(List<MovieContent>)? onPartial,
    bool Function()? isCanceled,
  }) async {
    final needle = _normalizeQuery(query);
    if (needle.length < 3 || !RegExp(r'[A-Za-z]').hasMatch(query)) {
      return const [];
    }
    const pageSize = 24;
    const maxCatalogPages = 8;
    const detailBatch = 8;
    final matches = <MovieContent>[];
    final seen = <String>{};

    Future<String?> originalOf(MovieContent item) async {
      try {
        final data = await _detailData(item.id);
        final detail = _map(_list(data['detiles']).firstOrNull);
        final original = _splitBiography(
          _plainDescription(detail['description']),
        ).$2;
        if (original != null && original.isNotEmpty) {
          TitleLanguage.noteOriginalTitle(item.id, original);
          return original;
        }
      } catch (_) {}
      return null;
    }

    for (var catalogPage = 1;
        catalogPage <= maxCatalogPages &&
            matches.length < page * pageSize;
        catalogPage++) {
      if (isCanceled?.call() ?? false) return const [];
      List<MovieContent> items;
      try {
        final pages = await Future.wait([
          _catalogPage(ContentKind.movie, catalogPage),
          _catalogPage(ContentKind.series, catalogPage),
        ]);
        items = [...pages[0], ...pages[1]];
      } catch (_) {
        items = const [];
      }
      if (items.isEmpty) break;
      for (var offset = 0;
          offset < items.length && matches.length < page * pageSize;
          offset += detailBatch) {
        if (isCanceled?.call() ?? false) return const [];
        final batch = items.skip(offset).take(detailBatch).toList();
        final originals = await Future.wait(batch.map(originalOf));
        for (var i = 0; i < batch.length; i++) {
          final original = originals[i];
          if (original == null) continue;
          if (_normalizeQuery(original).contains(needle) &&
              seen.add(batch[i].id)) {
            matches.add(batch[i]);
          }
        }
        if (matches.isNotEmpty) {
          onPartial?.call(matches.take(page * pageSize).toList());
        }
      }
    }
    final start = (page - 1) * pageSize;
    if (start >= matches.length) return const [];
    return matches.skip(start).take(pageSize).toList();
  }

  Future<Map<String, dynamic>> _detailData(String id) =>
      _request('detials', {'id': id, 'is_mobile': '1'});

  /// متن توضیحات سرویس ترکیبی است: «نام اصلی : X … خلاصه: SUMMARY».
  /// نام اصلی جدا و خلاصه تمیز برمی‌گردد تا صفحه جزئیات کامل باشد.
  /// برخی توضیحات به‌جای «خلاصه:» از «خلاصه داستان» بدون دونقطه استفاده
  /// می‌کنند؛ در آن حالت هم نام اصلی از بلوک ابتدایی استخراج می‌شود.
  static (String summary, String? originalTitle) _splitBiography(String raw) {
    final summaryAt =
        RegExp(r'خلاصه(\s+داستان)?\s*:').firstMatch(raw) ??
        RegExp(r'خلاصه\s+داستان').firstMatch(raw);
    final head = summaryAt == null
        ? (raw.length > 400 ? raw.substring(0, 400) : raw)
        : raw.substring(0, summaryAt.start);
    final summary = summaryAt == null
        ? raw
        : raw.substring(summaryAt.end).trim();
    var original = RegExp(
      r'نام اصلی\s*:\s*(.+)',
      multiLine: true,
    ).firstMatch(head)?.group(1)?.trim();
    if (original != null) {
      original = original.split(RegExp(r'[\r\n]+')).first.trim();
      final genreAt = original.indexOf('ژانرها');
      if (genreAt > 0) original = original.substring(0, genreAt).trim();
      final countryAt = original.indexOf('کشور سازنده');
      if (countryAt > 0) original = original.substring(0, countryAt).trim();
      if (original.isEmpty) original = null;
    }
    return (summary.isEmpty ? raw : summary, original);
  }

  List<MovieEpisode> _episodesFromLinks(List<Map<String, dynamic>> links) =>
      links
          .map((link) {
            final url = _text(
              link['link'] ??
                  link['url'] ??
                  link['file'] ??
                  link['fileUrl'] ??
                  link['src'],
            );
            return MovieEpisode(
              id: _text(link['id'] ?? link['videos_id']),
              name: _text(link['name'] ?? link['title'] ?? link['label']),
              fileUrl: url,
              fileSize: _text(
                link['video_size'] ?? link['size'] ?? link['file_size'],
              ),
              fileType: _fileType(url),
            );
          })
          .where(
            (episode) => Uri.tryParse(episode.fileUrl)?.hasAuthority == true,
          )
          .toList();

  static String _fileType(String url) {
    final path = Uri.tryParse(url)?.path ?? '';
    final ext = path.split('.').lastOrNull?.toLowerCase() ?? '';
    if (RegExp(r'^(mp4|mkv|webm|avi|mov|m4v|ts)$').hasMatch(ext)) return ext;
    return '';
  }

  @override
  Future<MovieContent> details(MovieContent summary) async {
    try {
      final data = await _detailData(summary.id);
      final row = _map(
        _list(data['detiles'] ?? data['details'] ?? data['detile']).firstOrNull,
      );
      if (row.isEmpty) throw const FormatException('جزئیات خالی است');
      final rawDescription = _plainDescription(
        row['description'] ??
            row['des'] ??
            row['story'] ??
            row['plot'] ??
            row['summary'] ??
            row['bio'] ??
            row['about'],
      );
      final biography = _splitBiography(rawDescription);
      final description = rawDescription;
      final alternateTitles = biography.$2 == null
          ? const <String>[]
          : <String>[biography.$2!];
      final linkGroups = _list(row['download_link']).map(_map).toList();
      final flatLinks = linkGroups
          .where((group) => group['link'] != null)
          .toList();
      final flatEpisodes = _episodesFromLinks(flatLinks);
      // کیفیت‌های تخت فیلم + لینک‌های تودرتوی فصل‌ها (سریال) در تب دانلود
      // یکجا دیده می‌شوند تا دکمه «دانلود همه کیفیت‌ها» برای سریال خالی نماند.
      final nestedEpisodes = [
        for (final group in linkGroups)
          ..._episodesFromLinks(_list(group['links']).map(_map).toList()),
      ];
      final allDownloads = <MovieDownload>[
        for (final episode in [...flatEpisodes, ...nestedEpisodes])
          MovieDownload(
            id: episode.id,
            label: episode.name,
            url: episode.fileUrl,
            fileSize: episode.fileSize,
          ),
      ];
      // حذف تکراری‌ها بر اساس نشانی فایل.
      final seenUrls = <String>{};
      final downloads = [
        for (final item in allDownloads)
          if (seenUrls.add(item.url)) item,
      ];
      final movieEpisodes = flatEpisodes
          .map(
            (episode) => MovieEpisode(
              id: episode.id,
              name: episode.name.isEmpty ? 'پخش فیلم' : episode.name,
              fileUrl: episode.fileUrl,
              fileSize: episode.fileSize,
              fileType: episode.fileType,
            ),
          )
          .toList();
      final seasons = <MovieSeason>[
        if (movieEpisodes.isNotEmpty)
          MovieSeason(
            id: 'movie',
            name: 'کیفیت‌های پخش',
            episodes: movieEpisodes,
          ),
        for (final (index, group) in linkGroups.indexed)
          if (_list(group['links']).isNotEmpty)
            MovieSeason(
              id: 'season-$index',
              name: _text(group['session_title']).isEmpty
                  ? 'فصل ${index + 1}'
                  : _text(group['session_title']),
              episodes: _episodesFromLinks(
                _list(group['links']).map(_map).toList(),
              ),
            ),
      ]..removeWhere((season) => season.episodes.isEmpty);
      final image = _text(
        row['poster_url'] ??
            row['thumbnail_url'] ??
            row['poster'] ??
            row['pic'] ??
            row['image'] ??
            row['cover'],
      );
      final genres = _text(row['genre'] ?? row['genres'])
          .split(RegExp(r'[,،]'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty && !_adult(part))
          .toList();
      final countries = _text(row['country'] ?? row['countries'])
          .split(RegExp(r'[,،]'))
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      final castRows = _list(data['casts']).isNotEmpty
          ? _list(data['casts'])
          : _list(row['casts']);
      final cast = castRows
          .map(_map)
          .map(
            (person) => MoviePerson(
              id: _text(person['id']),
              name: _text(person['name']),
              imageUrl: _text(person['pic_url']),
              role: _text(person['action_user']),
            ),
          )
          .where((person) => person.id.isNotEmpty && person.name.isNotEmpty)
          .toList();
      final kind = _kind(row, summary.kind);
      final related = [
        ..._items(row['related_movie'], kind),
        ..._items(row['related_tvseries'], kind),
        ..._items(row['related'], kind),
      ];
      final relatedSeen = <String>{};
      final relatedUnique = [
        for (final item in related)
          if (relatedSeen.add(item.id)) item,
      ];
      final trailer = _text(row['trailer_url'] ?? row['trailer']);
      final isDubbed =
          _text(
            row['is_duble'] ?? row['is_dubbed'] ?? row['dubbed'],
          ).toUpperCase() ==
          'T';
      final shareText = _text(row['shareText'] ?? row['share_text']);
      final year =
          int.tryParse(
            _text(row['year'] ?? row['sal'] ?? row['release_year']),
          ) ??
          summary.year;
      final rating =
          double.tryParse(
            _text(
              row['imdb_rating'] ?? row['imdb'] ?? row['rate'] ?? row['rating'],
            ),
          ) ??
          summary.rating;
      return MovieContent(
        id: summary.id,
        title: _text(row['title']).isEmpty
            ? summary.title
            : _text(row['title']),
        subtitle: kind == ContentKind.series ? 'سریال' : 'فیلم',
        description: description,
        year: year,
        rating: rating,
        kind: kind,
        colors: summary.colors,
        genres: genres,
        countries: countries,
        alternateTitles: alternateTitles,
        imageUrl: image.isEmpty ? summary.imageUrl : image,
        backdropUrl: image.isEmpty ? summary.backdropUrl : image,
        cast: cast,
        downloads: downloads,
        seasons: seasons,
        related: relatedUnique,
        trailerUrl: trailer.isEmpty ? null : trailer,
        isDubbed: isDubbed,
        shareText: shareText,
      );
    } catch (_) {
      throw const MovieApiException('جزئیات این عنوان قابل خواندن نیست.');
    }
  }

  @override
  Future<List<MovieComment>> comments(String contentId) async {
    try {
      final data = await _detailData(contentId);
      return _list(data['comments'])
          .map(_map)
          .map((row) {
            final admin = _text(row['des_admin']);
            var text = _text(row['des']);
            if (admin.isNotEmpty) text = '$text\n\nپاسخ مدیر: $admin';
            var user = _text(row['name']);
            if (user.isEmpty) user = 'کاربر MBNMovie';
            return MovieComment(
              id: _text(row['id']),
              userName: user,
              text: text,
            );
          })
          .where((comment) => comment.text.isNotEmpty)
          .toList();
    } catch (_) {
      throw const MovieApiException('نظرات این عنوان قابل خواندن نیست.');
    }
  }
}
