import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_content.dart';

class LibraryStore {
  static const _favoritesKey = 'library_favorites_v1';
  static const _historyKey = 'library_history_v1';

  Future<List<MovieContent>> favorites() => _read(_favoritesKey);
  Future<List<MovieContent>> history() => _read(_historyKey);

  Future<void> saveFavorites(Iterable<MovieContent> items) =>
      _write(_favoritesKey, items);

  Future<void> addToHistory(MovieContent item) async {
    final items = await history();
    items.removeWhere((current) => current.id == item.id);
    items.insert(0, item);
    await _write(_historyKey, items.take(50));
  }

  Future<void> saveHistory(Iterable<MovieContent> items) =>
      _write(_historyKey, items.take(50));

  Future<void> clearHistory() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_historyKey);
  }

  Future<List<MovieContent>> _read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(_decode)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _write(String key, Iterable<MovieContent> items) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      key,
      jsonEncode(items.map(_encode).toList(growable: false)),
    );
  }

  Map<String, Object?> _encode(MovieContent item) => {
    'id': item.id,
    'title': item.title,
    'subtitle': item.subtitle,
    'description': item.description,
    'year': item.year,
    'rating': item.rating,
    'kind': item.kind.name,
    'colors': item.colors.map((color) => color.toARGB32()).toList(),
    'genres': item.genres,
    'imageUrl': item.imageUrl,
    'backdropUrl': item.backdropUrl,
    'detailUrl': item.detailUrl,
    'tags': item.tags,
  };

  MovieContent _decode(Map<String, dynamic> row) {
    final kindName = row['kind']?.toString();
    final kind = ContentKind.values.where((value) => value.name == kindName);
    final colors = (row['colors'] as List<dynamic>? ?? const [])
        .whereType<num>()
        .map((value) => Color(value.toInt()))
        .toList();
    final storedImage = row['imageUrl']?.toString();
    final storedBackdrop = row['backdropUrl']?.toString();
    final legacyLandscapeInImage =
        storedImage?.contains('/poster_image/') ?? false;
    final imageUrl = legacyLandscapeInImage
        ? ((storedBackdrop?.contains('/video_thumb/') ?? false)
              ? storedBackdrop
              : storedImage?.replaceFirst('/poster_image/', '/video_thumb/'))
        : storedImage;
    final backdropUrl = legacyLandscapeInImage
        ? storedImage
        : (storedBackdrop ??
              storedImage?.replaceFirst('/video_thumb/', '/poster_image/'));
    // سازگاری با رکوردهای قدیمی: مقادیر حذفی نادیده گرفته می‌شوند.
    var kindValue = kind.isEmpty ? ContentKind.movie : kind.first;
    if (kindName == 'anime') kindValue = ContentKind.movie;
    return MovieContent(
      id: row['id']?.toString() ?? '',
      title: row['title']?.toString() ?? 'بدون عنوان',
      subtitle: row['subtitle']?.toString() ?? '',
      description: row['description']?.toString() ?? '',
      year: (row['year'] as num?)?.toInt() ?? DateTime.now().year,
      rating: (row['rating'] as num?)?.toDouble() ?? 0,
      kind: kindValue,
      colors: colors.length >= 2
          ? colors
          : const [Color(0xFFEF8354), Color(0xFF3D193A)],
      genres: (row['genres'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
      imageUrl: imageUrl,
      backdropUrl: backdropUrl,
      detailUrl: row['detailUrl']?.toString(),
      tags: (row['tags'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(),
    );
  }
}
