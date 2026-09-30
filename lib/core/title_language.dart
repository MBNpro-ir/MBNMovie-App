import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_content.dart';

/// Local display preference. Search always checks both Persian and original titles.
class TitleLanguage {
  TitleLanguage._();

  static const preferenceKey = 'movie_titles_english';
  static final revision = ValueNotifier<int>(0);
  static bool english = false;
  static final Map<String, String> _originalById = {};

  /// Offline English/original title for [id], if the bundled catalog knows it.
  /// Used by search so Latin queries match even when the server only sends
  /// Persian rows (no network needed).
  static String? originalTitleFor(String id) => _originalById[id];

  /// Remembers an original title learned at runtime (e.g. from a detail
  /// page's "نام اصلی") for the rest of this session, so later searches and
  /// English-title views can use it without another request.
  static void noteOriginalTitle(String id, String title) {
    final clean = title.trim();
    if (id.isEmpty || clean.isEmpty || _originalById.containsKey(id)) return;
    _originalById[id] = clean;
    revision.value++;
  }

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    english = prefs.getBool(preferenceKey) ?? false;
    try {
      final source = await rootBundle.loadString('assets/catalog_index.json');
      final rows = jsonDecode(source) as List<dynamic>;
      for (final value in rows) {
        if (value is! Map) continue;
        final id = value['id']?.toString() ?? '';
        final aliases = value['aliases'];
        if (id.isEmpty || aliases is! List) continue;
        for (final alias in aliases) {
          final original = alias?.toString().trim() ?? '';
          if (RegExp(r'[A-Za-z]').hasMatch(original)) {
            _originalById[id] = original;
            break;
          }
        }
      }
    } catch (_) {
      // Visible Persian titles remain usable if the offline index is missing.
    }
    revision.value++;
  }

  static Future<void> setEnglish(bool value) async {
    english = value;
    revision.value++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(preferenceKey, value);
  }

  static String title(MovieContent item) {
    if (!english) return item.title;
    for (final alias in item.alternateTitles) {
      if (RegExp(r'[A-Za-z]').hasMatch(alias)) return alias;
    }
    return _originalById[item.id] ?? item.title;
  }
}
