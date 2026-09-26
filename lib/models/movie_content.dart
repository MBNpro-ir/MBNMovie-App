import 'package:flutter/material.dart';

enum ContentKind { movie, series }

class MovieEpisode {
  const MovieEpisode({
    required this.id,
    required this.name,
    required this.fileUrl,
    this.imageUrl,
    this.fileType = '',
    this.fileSize = '',
  });

  final String id;
  final String name;
  final String fileUrl;
  final String? imageUrl;
  final String fileType;
  final String fileSize;
}

class MovieSeason {
  const MovieSeason({
    required this.id,
    required this.name,
    required this.episodes,
  });

  final String id;
  final String name;
  final List<MovieEpisode> episodes;
}

class MoviePerson {
  const MoviePerson({
    required this.id,
    required this.name,
    this.imageUrl,
    this.role = '',
  });

  final String id;
  final String name;
  final String? imageUrl;

  /// نقش در عنوان (بازیگر/کارگردان/...) از فیلد action_user سرویس.
  final String role;
}

class MovieDownload {
  const MovieDownload({
    required this.id,
    required this.label,
    required this.url,
    this.fileSize = '',
  });

  final String id;
  final String label;
  final String url;
  final String fileSize;
}

class MovieComment {
  const MovieComment({
    required this.id,
    required this.userName,
    required this.text,
    this.userImageUrl,
  });

  final String id;
  final String userName;
  final String text;
  final String? userImageUrl;
}

class MovieContent {
  const MovieContent({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.year,
    required this.rating,
    required this.kind,
    required this.colors,
    required this.genres,
    this.episodes = 0,
    this.progress = 0,
    this.imageUrl,
    this.backdropUrl,
    this.detailUrl,
    this.seasons = const [],
    this.imdbId,
    this.runtime = '',
    this.alternateTitles = const [],
    this.countries = const [],
    this.directors = const [],
    this.cast = const [],
    this.related = const [],
    this.downloads = const [],
    this.tags = const [],
    this.trailerUrl,
    this.isDubbed = false,
    this.shareText = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final String description;
  final int year;
  final double rating;
  final ContentKind kind;
  final List<Color> colors;
  final List<String> genres;
  final int episodes;
  final double progress;
  final String? imageUrl;

  /// Alternate artwork candidate. Its role is verified from decoded image
  /// dimensions because legacy API records can interchange the two fields.
  final String? backdropUrl;
  final String? detailUrl;
  final List<MovieSeason> seasons;
  final String? imdbId;
  final String runtime;
  final List<String> alternateTitles;
  final List<String> countries;
  final List<MoviePerson> directors;
  final List<MoviePerson> cast;
  final List<MovieContent> related;
  final List<MovieDownload> downloads;

  /// برچسب‌ها جدا از ژانرها.
  final List<String> tags;

  /// نشانی پیش‌نمایش و وضعیت دوبله از سرویس کاتالوگ.
  final String? trailerUrl;
  final bool isDubbed;
  final String shareText;

  String get kindLabel => switch (kind) {
    ContentKind.movie => 'فیلم',
    ContentKind.series => 'سریال',
  };

  String get ratingLabel => rating == rating.roundToDouble()
      ? rating.toStringAsFixed(0)
      : rating.toStringAsFixed(1);
}
