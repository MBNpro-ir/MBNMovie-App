import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_content.dart';

/// A user-created named playlist of titles.
class MoviePlaylist {
  const MoviePlaylist({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAtMs,
  });

  final String id;
  final String name;
  final List<MovieContent> items;
  final int createdAtMs;

  MoviePlaylist copyWith({String? name, List<MovieContent>? items}) =>
      MoviePlaylist(
        id: id,
        name: name ?? this.name,
        items: items ?? this.items,
        createdAtMs: createdAtMs,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAtMs': createdAtMs,
    'items': items.map(_encodeItem).toList(growable: false),
  };

  static MoviePlaylist? fromJson(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final name = row['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final items = (row['items'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_decodeItem)
        .where((item) => item.id.isNotEmpty)
        .toList();
    return MoviePlaylist(
      id: id,
      name: name,
      items: items,
      createdAtMs: (row['createdAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Persists user-created playlists locally.
class PlaylistStore {
  static const _key = 'user_playlists_v1';

  Future<List<MoviePlaylist>> playlists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(MoviePlaylist.fromJson)
          .whereType<MoviePlaylist>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<MoviePlaylist> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('نام پلی‌لیست خالی است');
    final lists = await playlists();
    final playlist = MoviePlaylist(
      id: 'pl-${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed,
      items: const [],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    lists.insert(0, playlist);
    await _write(lists);
    return playlist;
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final lists = await playlists();
    final index = lists.indexWhere((list) => list.id == id);
    if (index < 0) return;
    lists[index] = lists[index].copyWith(name: trimmed);
    await _write(lists);
  }

  Future<void> delete(String id) async {
    final lists = await playlists();
    lists.removeWhere((list) => list.id == id);
    await _write(lists);
  }

  /// Inserts a playlist received from sync (keeps its id). No-op when an
  /// entry with the same id already exists.
  Future<void> importPlaylist(MoviePlaylist playlist) async {
    final lists = await playlists();
    if (lists.any((list) => list.id == playlist.id)) return;
    lists.insert(0, playlist);
    await _write(lists);
  }

  /// Adds [item] to the playlist unless it is already there. Returns true
  /// when the playlist changed.
  Future<bool> addTitle(String listId, MovieContent item) async {
    final lists = await playlists();
    final index = lists.indexWhere((list) => list.id == listId);
    if (index < 0) return false;
    final current = lists[index];
    if (current.items.any((old) => old.id == item.id)) return false;
    lists[index] = current.copyWith(items: [...current.items, item]);
    await _write(lists);
    return true;
  }

  Future<bool> removeTitle(String listId, String contentId) async {
    final lists = await playlists();
    final index = lists.indexWhere((list) => list.id == listId);
    if (index < 0) return false;
    final current = lists[index];
    final next = current.items
        .where((item) => item.id != contentId)
        .toList();
    if (next.length == current.items.length) return false;
    lists[index] = current.copyWith(items: next);
    await _write(lists);
    return true;
  }

  Future<Set<String>> listIdsContaining(String contentId) async {
    final lists = await playlists();
    return {
      for (final list in lists)
        if (list.items.any((item) => item.id == contentId)) list.id,
    };
  }

  Future<void> _write(List<MoviePlaylist> lists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(lists.map((list) => list.toJson()).toList(growable: false)),
    );
  }
}

Map<String, Object?> _encodeItem(MovieContent item) => {
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

MovieContent _decodeItem(Map<String, dynamic> row) {
  final kindName = row['kind']?.toString();
  final kind = ContentKind.values.where((value) => value.name == kindName);
  var kindValue = kind.isEmpty ? ContentKind.movie : kind.first;
  if (kindName == 'anime') kindValue = ContentKind.movie;
  final colors = (row['colors'] as List<dynamic>? ?? const [])
      .whereType<num>()
      .map((value) => Color(value.toInt()))
      .toList();
  return MovieContent(
    id: row['id']?.toString() ?? '',
    title: row['title']?.toString() ?? 'بدون عنوان',
    subtitle: row['subtitle']?.toString() ?? '',
    description: row['description']?.toString() ?? '',
    year: (row['year'] as num?)?.toInt() ?? 0,
    rating: (row['rating'] as num?)?.toDouble() ?? 0,
    kind: kindValue,
    colors: colors.length >= 2
        ? colors
        : const [Color(0xFF4665B3), Color(0xFF10182B)],
    genres: (row['genres'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(),
    imageUrl: row['imageUrl']?.toString(),
    backdropUrl: row['backdropUrl']?.toString(),
    detailUrl: row['detailUrl']?.toString(),
    tags: (row['tags'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList(),
  );
}
