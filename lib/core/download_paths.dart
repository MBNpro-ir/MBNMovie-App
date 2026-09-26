import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/movie_content.dart';

/// ASCII-only folder names; untranslated names get a stable unique fallback.
String englishDownloadFolder(String input, String fallback) {
  var text = input;
  const digits = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < digits.length; i++) {
    text = text.replaceAll(digits[i], '${i % 10}');
  }
  text = text
      .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (!RegExp(r'[A-Za-z0-9]').hasMatch(text)) text = fallback;
  return safeDownloadComponent(text);
}

List<String> downloadFolderParts(MovieContent content, MovieSeason season) {
  final titles = [content.title, ...content.alternateTitles];
  final title = titles.firstWhere(
    (value) =>
        RegExp(r'^[\x20-\x7e]+$').hasMatch(value) &&
        RegExp(r'[A-Za-z]').hasMatch(value),
    orElse: () => 'Title',
  );
  return [
    switch (content.kind) {
      ContentKind.movie => 'Movies',
      ContentKind.series => 'Series',
    },
    '${englishDownloadFolder(title, 'Title')} (${content.year})-${downloadIdentity(content.id, '', '').substring(0, 8)}',
    'Season-${englishDownloadFolder(season.name, 'Unknown')}-${downloadIdentity(content.id, season.id, '').substring(0, 8)}',
  ];
}

String safeDownloadComponent(String input) {
  var value = input
      .replaceAll(RegExp(r'[\x00-\x1f\\/:*?"<>|]'), '-')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (value.isEmpty || value == '.' || value == '..') value = 'بدون نام';
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(value)) {
    value = '_$value';
  }
  return String.fromCharCodes(value.runes.take(65));
}

String downloadIdentity(String contentId, String seasonId, String episodeId) =>
    sha256
        .convert(utf8.encode(jsonEncode([contentId, seasonId, episodeId])))
        .toString()
        .substring(0, 16);

String episodeDownloadFilename(MovieEpisode episode, String identity) {
  var extension = episode.fileType.toLowerCase().trim();
  if (!RegExp(r'^(mp4|mkv|webm|avi|mov|m4v|ts)$').hasMatch(extension)) {
    extension =
        Uri.tryParse(episode.fileUrl)?.path.split('.').last.toLowerCase() ??
        'mp4';
  }
  if (!RegExp(r'^(mp4|mkv|webm|avi|mov|m4v|ts)$').hasMatch(extension)) {
    extension = 'mp4';
  }
  return '${safeDownloadComponent(episode.name)}-$identity.$extension';
}
