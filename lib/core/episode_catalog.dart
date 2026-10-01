import '../models/movie_content.dart';

class EpisodeVariant {
  const EpisodeVariant({
    required this.season,
    required this.episode,
    required this.quality,
  });

  final MovieSeason season;
  final MovieEpisode episode;
  final String quality;
}

/// برچسب پیش‌فرض وقتی هیچ کیفیتی (480p و...) از نام فصل/قسمت پیدا نشود.
const unknownQualityLabel = 'بدون برچسب کیفیت';

/// true وقتی [quality] همان «بدون برچسب کیفیت» است — شامل حالت‌های
/// چند سروره مثل «بدون برچسب کیفیت · سرور 2».
bool isUnknownQuality(String quality) =>
    quality == unknownQualityLabel ||
    quality.startsWith('$unknownQualityLabel ·') ||
    quality.startsWith('$unknownQualityLabel •');

/// true وقتی متن به تیزر/تریلر اشاره دارد (فارسی یا انگلیسی).
bool isTrailerLabel(String value) =>
    RegExp(r'تیزر|trailer|teaser', caseSensitive: false).hasMatch(value);

/// برچسب نمایشی کیفیت: «بدون برچسب کیفیت» به «پخش» تبدیل می‌شود و
/// پسوند سرور حفظ می‌ماند («بدون برچسب کیفیت · سرور 2» ← «سرور 2»).
String qualityDisplayLabel(String quality) {
  if (quality == unknownQualityLabel) return 'پخش';
  final server = RegExp(r'·\s*(سرور\s*.+)').firstMatch(quality);
  if (server != null && quality.startsWith(unknownQualityLabel)) {
    return server.group(1)!.trim();
  }
  final dotServer = RegExp(r'•\s*(سرور\s*.+)').firstMatch(quality);
  if (dotServer != null && quality.startsWith(unknownQualityLabel)) {
    return dotServer.group(1)!.trim();
  }
  return quality;
}

class EpisodeGroup {
  const EpisodeGroup({
    required this.id,
    required this.name,
    required this.variants,
  });

  final String id;
  final String name;
  final List<EpisodeVariant> variants;

  /// true وقتی این گروه مربوط به تیزر است (شناسه منطقی trailer یا نام تیزر).
  bool get isTrailer => id.contains('trailer') || isTrailerLabel(name);

  EpisodeVariant variantFor(String? quality) {
    if (quality != null) {
      for (final variant in variants) {
        if (variant.quality == quality) return variant;
      }
    }
    return variants.first;
  }

  bool contains(MovieEpisode episode) => variants.any(
    (variant) =>
        variant.episode.id == episode.id &&
        variant.episode.fileUrl == episode.fileUrl,
  );
}

class EpisodeSeasonGroup {
  const EpisodeSeasonGroup({
    required this.id,
    required this.name,
    required this.episodes,
  });

  final String id;
  final String name;
  final List<EpisodeGroup> episodes;

  List<String> get qualities =>
      _qualityList(episodes.expand((episode) => episode.variants));

  /// true وقتی این فصل همان فصل تیزرها است.
  bool get isTrailerSeason => id == 'trailer';

  /// کیفیت‌های نمایشی فصل — بدون آلودگی تیزرها:
  /// - فصل تیزرها: فقط کیفیت‌های واقعی (معمولاً خالی → انتخاب‌گر کیفیت مخفی).
  /// - فصل فیلم/سریال عادی: کیفیت تیزرها (معمولاً «بدون برچسب کیفیت»)
  ///   از فهرست حذف می‌شود تا چیپ اضافه نسازد؛ کیفیت‌های واقعی فیلم می‌ماند.
  /// - اگر هیچ واریانت غیرتیزری نبود، کیفیت‌های واقعی همه واریانت‌ها برمی‌گردد.
  List<String> get displayQualities {
    final allVariants = episodes.expand((episode) => episode.variants);
    if (isTrailerSeason) {
      return _qualityList(
        allVariants.where((variant) => !isUnknownQuality(variant.quality)),
      );
    }
    final nonTrailer = allVariants.where(
      (variant) =>
          !isTrailerLabel(variant.episode.name) &&
          !isTrailerLabel(variant.season.name),
    );
    final list = _qualityList(nonTrailer);
    if (list.isNotEmpty) return list;
    return _qualityList(
      allVariants.where((variant) => !isUnknownQuality(variant.quality)),
    );
  }
}

class EpisodeCatalog {
  const EpisodeCatalog({required this.seasons, required this.qualities});

  final List<EpisodeSeasonGroup> seasons;
  final List<String> qualities;

  Iterable<EpisodeGroup> get episodes =>
      seasons.expand((season) => season.episodes);

  EpisodeGroup? groupFor(MovieEpisode episode) {
    for (final group in episodes) {
      if (group.contains(episode)) return group;
    }
    return null;
  }

  /// Recover the real variant, including its raw id and quality metadata.
  /// Older last-watch records store a logical group id instead of a raw id.
  EpisodeVariant? resumeVariant({
    required String episodeId,
    required String fileUrl,
    String? preferredQuality,
  }) {
    for (final group in episodes) {
      for (final variant in group.variants) {
        if (variant.episode.fileUrl == fileUrl) return variant;
      }
    }
    for (final group in episodes) {
      if (group.id == episodeId) return group.variantFor(preferredQuality);
      for (final variant in group.variants) {
        if (variant.episode.id == episodeId) return variant;
      }
    }
    return null;
  }

  static EpisodeCatalog from(MovieContent content) {
    if (content.seasons.isEmpty) {
      return const EpisodeCatalog(seasons: [], qualities: []);
    }
    if (content.kind == ContentKind.movie &&
        content.seasons.length == 1 &&
        content.seasons.first.id == 'movie') {
      final raw = content.seasons.first;
      final all = raw.episodes
          .map(
            (episode) => EpisodeVariant(
              season: raw,
              episode: episode,
              quality: episodeQuality(raw.name, episode.name),
            ),
          )
          .toList(growable: false);
      // تیزر فیلم نباید به‌عنوان یک «کیفیت» (معمولاً «بدون برچسب کیفیت»)
      // قاطی نسخه‌های اصلی شود؛ جدا می‌شود تا چیپ کیفیت را آلوده نکند.
      final mains = all
          .where(
            (variant) =>
                !isTrailerLabel(variant.episode.name) &&
                !isTrailerLabel(raw.name),
          )
          .toList(growable: false);
      final trailers = all
          .where(
            (variant) =>
                isTrailerLabel(variant.episode.name) ||
                isTrailerLabel(raw.name),
          )
          .toList(growable: false);
      if (mains.isEmpty) {
        // فقط تیزر موجود است: همان را بدون آلودگی کیفیت نمایش بده.
        final trailerGroups = [
          for (final variant in trailers)
            EpisodeGroup(
              id: 'logical:movie:trailer-${variant.episode.id}',
              name: variant.episode.name.isEmpty
                  ? 'تیزر'
                  : variant.episode.name,
              variants: [variant],
            ),
        ];
        final fallbackVariants = trailerGroups.isEmpty
            ? const <EpisodeVariant>[]
            : trailerGroups.expand((group) => group.variants);
        return EpisodeCatalog(
          seasons: [
            EpisodeSeasonGroup(
              id: 'movie',
              name: 'فیلم',
              episodes: trailerGroups.isEmpty
                  ? [
                      EpisodeGroup(
                        id: 'logical:movie:main',
                        name: 'پخش فیلم',
                        variants: _uniqueVariants(all),
                      ),
                    ]
                  : trailerGroups,
            ),
          ],
          qualities: _qualityList(fallbackVariants),
        );
      }
      final trailerGroups = [
        for (final variant in trailers)
          EpisodeGroup(
            id: 'logical:movie:trailer-${variant.episode.id}',
            name: variant.episode.name.isEmpty ? 'تیزر' : variant.episode.name,
            variants: [variant],
          ),
      ];

      // دسته‌بندی نسخه‌های مختلف فیلم (مثل دوبله فارسی، زیرنویس فارسی، زبان اصلی)
      final categoryBuckets = <String, List<EpisodeVariant>>{};
      for (final variant in mains) {
        final catKey = _movieCategoryKey(variant.episode.name);
        categoryBuckets.putIfAbsent(catKey, () => []).add(variant);
      }

      if (categoryBuckets.length <= 1) {
        final mainVariants = _uniqueVariants(mains);
        return EpisodeCatalog(
          seasons: [
            EpisodeSeasonGroup(
              id: 'movie',
              name: 'فیلم',
              episodes: [
                EpisodeGroup(
                  id: 'logical:movie:main',
                  name: 'پخش فیلم',
                  variants: mainVariants,
                ),
                ...trailerGroups,
              ],
            ),
          ],
          qualities: _qualityList(mainVariants),
        );
      }

      final sortedKeys = categoryBuckets.keys.toList()
        ..sort((a, b) {
          final orderA = _categoryOrder(a);
          final orderB = _categoryOrder(b);
          return orderA != orderB ? orderA.compareTo(orderB) : a.compareTo(b);
        });

      final movieSeasons = <EpisodeSeasonGroup>[];
      final allMainVariants = <EpisodeVariant>[];

      for (var i = 0; i < sortedKeys.length; i++) {
        final key = sortedKeys[i];
        final variants = _uniqueVariants(categoryBuckets[key]!);
        allMainVariants.addAll(variants);
        final title = _movieCategoryTitle(key, variants.first.episode.name);
        movieSeasons.add(
          EpisodeSeasonGroup(
            id: 'movie-$key',
            name: title,
            episodes: [
              EpisodeGroup(
                id: 'logical:movie:$key',
                name: 'پخش فیلم',
                variants: variants,
              ),
              if (i == 0) ...trailerGroups,
            ],
          ),
        );
      }

      return EpisodeCatalog(
        seasons: movieSeasons,
        qualities: _qualityList(allMainVariants),
      );
    }

    final seasonBuckets = <String, List<(int, MovieSeason)>>{};
    for (final (index, season) in content.seasons.indexed) {
      final key = _seasonKey(season.name, index);
      seasonBuckets.putIfAbsent(key, () => []).add((index, season));
    }
    final groupedSeasons = <EpisodeSeasonGroup>[];
    final allVariants = <EpisodeVariant>[];
    for (final entry in seasonBuckets.entries) {
      final episodeBuckets = <String, List<(int, EpisodeVariant)>>{};
      for (final (_, season) in entry.value) {
        for (final (episodeIndex, episode) in season.episodes.indexed) {
          final key = _episodeKey(episode.name, episodeIndex);
          final variant = EpisodeVariant(
            season: season,
            episode: episode,
            quality: episodeQuality(season.name, episode.name),
          );
          episodeBuckets.putIfAbsent(key, () => []).add((
            episodeIndex,
            variant,
          ));
        }
      }
      final groups = <EpisodeGroup>[];
      for (final bucket in episodeBuckets.entries) {
        final variants = _uniqueVariants(bucket.value.map((item) => item.$2));
        allVariants.addAll(variants);
        final first = variants.first;
        final isTrailerGroup =
            bucket.key.startsWith('trailer-') ||
            entry.key == 'trailer' ||
            isTrailerLabel(first.episode.name);
        groups.add(
          EpisodeGroup(
            id: 'logical:${entry.key}:${bucket.key}',
            name: isTrailerGroup
                ? first.episode.name
                : episodeDisplayName(first.episode.name),
            variants: variants,
          ),
        );
      }
      groups.sort((a, b) => _naturalCompare(a.name, b.name));
      groupedSeasons.add(
        EpisodeSeasonGroup(
          id: entry.key,
          name: _seasonDisplayName(entry.key, entry.value.first.$2.name),
          episodes: groups,
        ),
      );
    }
    groupedSeasons.sort((a, b) => _naturalCompare(a.name, b.name));
    return EpisodeCatalog(
      seasons: groupedSeasons,
      qualities: _qualityList(allVariants),
    );
  }
}

/// نام نمایشی یک قسمت سریال: رکوردهای API گاهی فقط عددند («3») یا
/// ستاره دارند («4*» در داده خام که در رابط راست‌به‌چپ «*4» دیده می‌شود)؛
/// همه به «قسمت N» یکدست می‌شوند. نام‌هایی که از قبل «قسمت» دارند یا
/// توصیفی‌اند دست نخورده می‌مانند. فقط برای نمایش است و
/// شناسه/آدرس فایل را تغییر نمی‌دهد.
String episodeDisplayName(String rawName) {
  final name = rawName.trim();
  if (name.isEmpty) return 'قسمت';
  if (isTrailerLabel(name)) return name;

  final latin = _latinDigits(name).toLowerCase();

  final epMatch = RegExp(
    r'(?:قسمت|episode|ep|part)\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(latin);
  if (epMatch != null) {
    return 'قسمت ${int.parse(epMatch.group(1)!)}';
  }

  final bare =
      RegExp(r'^\*?\s*(\d+)\b').firstMatch(latin) ??
      RegExp(r'\b(\d+)\s*\*?$').firstMatch(latin);
  if (bare != null) {
    return 'قسمت ${int.parse(bare.group(1)!)}';
  }

  final cleaned = _cleanQualityTokens(name);
  return cleaned.isEmpty ? 'قسمت' : cleaned;
}

String _formatQualityWithModifier(int pixels, String contextText) {
  final lower = contextText.toLowerCase();
  final modifiers = <String>[];

  // HD / HQ release modifier (for 1080p, indicates higher bitrate/uncompressed bluray vs standard web-dl)
  if (pixels >= 1080) {
    final isStandAloneHd =
        (RegExp(r'\b(hd|hq)\b').hasMatch(lower) ||
            RegExp(r'اچ\s*دی').hasMatch(lower)) &&
        !RegExp(r'\bfhd\b').hasMatch(lower) &&
        !RegExp(r'فول\s*اچ\s*دی').hasMatch(lower) &&
        !RegExp(r'full\s*hd').hasMatch(lower);
    if (isStandAloneHd) {
      modifiers.add('HD');
    }
  }

  if (RegExp(r'\b(x265|hevc)\b').hasMatch(lower)) {
    modifiers.add('x265');
  }

  if (RegExp(r'\b10bit\b').hasMatch(lower)) {
    modifiers.add('10bit');
  }

  if (RegExp(r'\bimax\b').hasMatch(lower)) {
    modifiers.add('IMAX');
  }

  if (RegExp(r'\b3d\b').hasMatch(lower)) {
    modifiers.add('3D');
  }

  if (modifiers.isEmpty) {
    return '${pixels}p';
  }
  return '${pixels}p ${modifiers.join(' ')}';
}

String episodeQuality(String seasonName, String episodeName) {
  final value = _latinDigits('$seasonName $episodeName');
  final pixelsMatch = RegExp(
    r'(?<!\d)(\d{3,4})\s*[pP](?!\w)',
  ).firstMatch(value)?.group(1);
  if (pixelsMatch != null) {
    return _formatQualityWithModifier(int.parse(pixelsMatch), value);
  }
  // برچسب‌های فارسی سرویس کاتالوگ: «کیفیت 720»، «کیفیت : 480»،
  // «720 کیفیت»، «دوبله 1080»...
  final faPixels =
      RegExp(r'کیفیت\s*:?\s*(\d{3,4})').firstMatch(value)?.group(1) ??
      RegExp(r'(\d{3,4})\s*:?\s*کیفیت').firstMatch(value)?.group(1);
  if (faPixels != null) {
    return _formatQualityWithModifier(int.parse(faPixels), value);
  }
  if (RegExp(r'\b(4k|uhd)\b', caseSensitive: false).hasMatch(value)) {
    final lower = value.toLowerCase();
    final mods = <String>[];
    if (lower.contains('imax')) mods.add('IMAX');
    if (lower.contains('10bit')) mods.add('10bit');
    if (lower.contains('x265') || lower.contains('hevc')) mods.add('x265');
    return mods.isEmpty ? '4K' : '4K ${mods.join(' ')}';
  }
  if (RegExp(r'\bfhd\b', caseSensitive: false).hasMatch(value) ||
      RegExp(r'فول\s*اچ\s*دی').hasMatch(value)) {
    return _formatQualityWithModifier(1080, value);
  }
  if (RegExp(r'\bhd\b', caseSensitive: false).hasMatch(value) ||
      RegExp(r'(^|\W)اچ\s*دی(\W|$)').hasMatch(value)) {
    return '720p';
  }
  if (RegExp(r'\bsd\b', caseSensitive: false).hasMatch(value)) return '480p';
  return unknownQualityLabel;
}

String recommendedEpisodeQuality(Iterable<String> qualities) {
  final values = qualities.toList(growable: false);
  if (values.contains('720p')) return '720p';
  return values.isEmpty ? unknownQualityLabel : values.first;
}

/// Formats a raw `file_size` value from the legacy API for display under an
/// episode: `55MB`, `1.2GB`. Bare numbers are megabytes (the API's unit);
/// values already carrying a unit are normalized (`1.2 GB` → `1.2GB`);
/// large byte counts are scaled down. Returns '' when there is no usable
/// size (the UI then falls back to «پخش آنلاین»).
String formatFileSize(String raw) {
  final text = _latinDigits(raw.trim());
  if (text.isEmpty) return '';
  // واحدهای فارسی سرویس کاتالوگ: «437 مگابایت»، «1.5 گیگابایت»...
  final faUnit = RegExp(
    r'^([\d.,]+)\s*(ترابایت|گیگابایت|مگابایت|کیلوبایت|بایت|گیگ|مگ|کیلو)',
  ).firstMatch(text);
  if (faUnit != null) {
    final number = double.tryParse(
      _trimSizeNumber(faUnit.group(1)!).replaceAll(',', ''),
    );
    if (number == null || number <= 0) return raw.trim();
    final unit = faUnit.group(2)!;
    String fixed(int fractionDigits) =>
        _trimSizeNumber(number.toStringAsFixed(fractionDigits));
    if (unit.startsWith('ترا')) return '${fixed(1)}TB';
    if (unit.startsWith('گیگ') || unit == 'گیگ') {
      return '${fixed(number < 10 ? 1 : 0)}GB';
    }
    if (unit.startsWith('مگا') || unit == 'مگ') {
      return '${fixed(number < 10 ? 1 : 0)}MB';
    }
    if (unit.startsWith('کیلو')) return '${fixed(0)}KB';
    return '${fixed(0)}B';
  }
  final withUnit = RegExp(
    r'^([\d.,]+)\s*([kKmMgGtT])\s*[bB]$',
  ).firstMatch(text);
  if (withUnit != null) {
    return '${_trimSizeNumber(withUnit.group(1)!)}'
        '${withUnit.group(2)!.toUpperCase()}B';
  }
  // Unknown trailing text (e.g. a word unit we do not recognize): keep it
  // untouched rather than inventing a wrong number.
  if (RegExp(r'[a-zA-Z]').hasMatch(text)) return raw.trim();
  final number = double.tryParse(text.replaceAll(',', ''));
  if (number == null || number <= 0) return '';
  if (number >= 1024 * 1024) {
    final mb = number / (1024 * 1024);
    if (mb >= 1024) {
      return '${_trimSizeNumber((mb / 1024).toStringAsFixed(1))}GB';
    }
    return '${_trimSizeNumber(mb.toStringAsFixed(mb < 10 ? 1 : 0))}MB';
  }
  return '${_trimSizeNumber(text)}MB';
}

String _trimSizeNumber(String value) {
  var text = value.replaceAll(',', '');
  if (text.contains('.')) {
    text = text.replaceAll(RegExp(r'0+$'), '');
    text = text.replaceAll(RegExp(r'\.$'), '');
  }
  return text;
}

/// یک بستهٔ دانلودی: چند قسمت/فایل هم‌کیفیت که با یک دکمه یکجا دانلود می‌شوند.
class QualityDownloadBatch {
  const QualityDownloadBatch({
    required this.label,
    required this.season,
    required this.episodes,
  });

  /// متن دکمه (مثلاً «فصل 1 · 720p · دانلود همه 12 قسمت»).
  final String label;

  /// فصل مصنوعی برای نام پوشه/فایل و شناسهٔ یکتای دانلود.
  final MovieSeason season;
  final List<MovieEpisode> episodes;
}

/// نقشهٔ دکمه‌های تب دانلود برای محتوا.
class NormalDownloadPlan {
  const NormalDownloadPlan({
    required this.isMovie,
    this.movieAll,
    required this.batches,
  });

  final bool isMovie;

  /// دکمهٔ «دانلود همه کیفیت‌ها» (فقط فیلم).
  final QualityDownloadBatch? movieAll;
  final List<QualityDownloadBatch> batches;
}

List<MovieEpisode> _distinctEpisodes(Iterable<MovieEpisode> input) {
  final seen = <String>{};
  return [
    for (final episode in input)
      if (episode.fileUrl.isNotEmpty && seen.add(episode.fileUrl)) episode,
  ];
}

/// دکمه‌های دانلود تب «قسمت‌ها و دانلود»:
/// - فیلم: «دانلود همه کیفیت‌ها» + تک‌تک کیفیت‌ها.
/// - سریال: برای هر فصل، همهٔ قسمت‌های هر کیفیت جداگانه
///   (بدون قاطی کردن چند کیفیت باهم)؛ تیزرها کنار گذاشته می‌شوند.
NormalDownloadPlan normalDownloadPlan(MovieContent content) {
  final catalog = EpisodeCatalog.from(content);
  final isMovie = content.kind == ContentKind.movie;
  if (isMovie) {
    if (catalog.seasons.length == 1 && catalog.seasons.first.id == 'movie') {
      final season = catalog.seasons.first;
      final main = season.episodes.firstWhere(
        (group) => group.id == 'logical:movie:main',
        orElse: () => season.episodes.first,
      );
      final mains = main.variants
          .where(
            (variant) =>
                !isTrailerLabel(variant.episode.name) &&
                !isTrailerLabel(variant.season.name),
          )
          .toList(growable: false);
      if (mains.isEmpty) {
        return const NormalDownloadPlan(isMovie: true, batches: []);
      }
      final qualities = _qualityList(mains);
      if (qualities.every(isUnknownQuality)) {
        final episodes = _distinctEpisodes(mains.map((item) => item.episode));
        return NormalDownloadPlan(
          isMovie: true,
          batches: [
            QualityDownloadBatch(
              label: 'دانلود فیلم',
              season: MovieSeason(
                id: 'movie-all',
                name: 'کیفیت‌های پخش',
                episodes: episodes,
              ),
              episodes: episodes,
            ),
          ],
        );
      }
      final known = qualities
          .where((quality) => !isUnknownQuality(quality))
          .toList(growable: false);
      final effective = known.isEmpty ? qualities : known;
      return NormalDownloadPlan(
        isMovie: true,
        movieAll: QualityDownloadBatch(
          label: 'دانلود همه ${mains.length} کیفیت',
          season: MovieSeason(
            id: 'movie-all',
            name: 'کیفیت‌های پخش',
            episodes: _distinctEpisodes(mains.map((item) => item.episode)),
          ),
          episodes: _distinctEpisodes(mains.map((item) => item.episode)),
        ),
        batches: [
          for (final quality in effective)
            for (final variant in mains.where(
              (item) => item.quality == quality,
            ))
              QualityDownloadBatch(
                label: 'دانلود کیفیت ${qualityDisplayLabel(quality)}',
                season: MovieSeason(
                  id: 'movie-$quality',
                  name: 'کیفیت‌های پخش · $quality',
                  episodes: [variant.episode],
                ),
                episodes: [variant.episode],
              ),
        ],
      );
    }

    // فیلم با چند دسته‌بندی (مثلاً دوبله فارسی، زیرنویس فارسی)
    final allMains = catalog.seasons
        .where((s) => !s.isTrailerSeason)
        .expand(
          (s) =>
              s.episodes.where((e) => !e.isTrailer).expand((e) => e.variants),
        )
        .toList(growable: false);
    if (allMains.isEmpty) {
      return const NormalDownloadPlan(isMovie: true, batches: []);
    }
    final batches = <QualityDownloadBatch>[];
    for (final season in catalog.seasons) {
      if (season.isTrailerSeason) continue;
      final mainVariants = season.episodes
          .where((e) => !e.isTrailer)
          .expand((e) => e.variants)
          .toList(growable: false);
      if (mainVariants.isEmpty) continue;
      for (final variant in mainVariants) {
        batches.add(
          QualityDownloadBatch(
            label:
                '${season.name} · کیفیت ${qualityDisplayLabel(variant.quality)}',
            season: MovieSeason(
              id: '${season.id}-${variant.quality}',
              name: '${season.name} · ${variant.quality}',
              episodes: [variant.episode],
            ),
            episodes: [variant.episode],
          ),
        );
      }
    }
    return NormalDownloadPlan(
      isMovie: true,
      movieAll: QualityDownloadBatch(
        label: 'دانلود همه ${allMains.length} نسخه',
        season: MovieSeason(
          id: 'movie-all',
          name: 'کیفیت‌های پخش',
          episodes: _distinctEpisodes(allMains.map((item) => item.episode)),
        ),
        episodes: _distinctEpisodes(allMains.map((item) => item.episode)),
      ),
      batches: batches,
    );
  }

  final batches = <QualityDownloadBatch>[];
  for (final season in catalog.seasons) {
    if (season.isTrailerSeason) continue;
    final groups = season.episodes
        .where((group) => !group.isTrailer)
        .toList(growable: false);
    if (groups.isEmpty) continue;
    final qualities = season.displayQualities;
    if (qualities.isEmpty) {
      final episodes = _distinctEpisodes(
        groups.expand((group) => group.variants.map((item) => item.episode)),
      );
      if (episodes.isEmpty) continue;
      batches.add(
        QualityDownloadBatch(
          label: '${season.name} · دانلود همه ${episodes.length} قسمت',
          season: MovieSeason(
            id: '${season.id}-all',
            name: season.name,
            episodes: episodes,
          ),
          episodes: episodes,
        ),
      );
      continue;
    }
    for (final quality in qualities) {
      final episodes = _distinctEpisodes([
        for (final group in groups)
          if (group.variants.any((item) => item.quality == quality))
            group.variantFor(quality).episode,
      ]);
      if (episodes.isEmpty) continue;
      batches.add(
        QualityDownloadBatch(
          label:
              '${season.name} · ${qualityDisplayLabel(quality)} · دانلود همه ${episodes.length} قسمت',
          season: MovieSeason(
            id: '${season.id}-$quality',
            name: '${season.name} · $quality',
            episodes: episodes,
          ),
          episodes: episodes,
        ),
      );
    }
  }
  return NormalDownloadPlan(isMovie: false, batches: batches);
}

List<EpisodeVariant> _uniqueVariants(Iterable<EpisodeVariant> input) {
  final values = <EpisodeVariant>[];
  final counts = <String, int>{};
  for (final variant in input) {
    if (values.any((item) => item.episode.fileUrl == variant.episode.fileUrl)) {
      continue;
    }
    final count = (counts[variant.quality] ?? 0) + 1;
    counts[variant.quality] = count;
    values.add(
      count == 1
          ? variant
          : EpisodeVariant(
              season: variant.season,
              episode: variant.episode,
              quality: _disambiguateQuality(variant, count),
            ),
    );
  }
  values.sort((a, b) {
    final rank = _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
    return rank != 0 ? rank : a.quality.compareTo(b.quality);
  });
  return List.unmodifiable(values);
}

String _disambiguateQuality(EpisodeVariant variant, int count) {
  final name = variant.episode.name;
  final cleaned = _cleanQualityTokens(name);
  if (cleaned.contains('کم حجم')) {
    return '${variant.quality} · کم‌حجم';
  }
  return '${variant.quality} · سرور $count';
}

List<String> _qualityList(Iterable<EpisodeVariant> variants) {
  final result = variants.map((item) => item.quality).toSet().toList()
    ..sort((a, b) {
      final rank = _qualityRank(b).compareTo(_qualityRank(a));
      return rank != 0 ? rank : a.compareTo(b);
    });
  return List.unmodifiable(result);
}

int _qualityRank(String value) {
  final lower = value.toLowerCase();
  var base = 0;
  if (lower.contains('4k') || lower.contains('2160')) {
    base = 2160;
  } else {
    base =
        int.tryParse(RegExp(r'\d{3,4}').firstMatch(value)?.group(0) ?? '') ?? 0;
  }

  var boost = 0;
  if (lower.contains('hd') || lower.contains('hq')) boost += 4;
  if (lower.contains('imax')) boost += 3;
  if (lower.contains('10bit')) boost += 2;
  if (lower.contains('x265') || lower.contains('hevc')) boost += 1;

  return base * 10 + boost;
}

int _categoryOrder(String key) {
  if (key.startsWith('dubbed')) return 1;
  switch (key) {
    case 'subbed':
      return 2;
    case 'original':
      return 3;
    case 'main':
      return 4;
    default:
      return 5;
  }
}

String _movieCategoryKey(String name) {
  final lower = _latinDigits(name).toLowerCase();
  if (lower.contains('دوبله') || lower.contains('farsi dub')) {
    for (final studio in const [
      'گلوری',
      'سورن',
      'کوالیما',
      'آواژه',
      'فیلیمو',
      'نماوا',
    ]) {
      if (lower.contains(studio)) {
        return 'dubbed-$studio';
      }
    }
    return 'dubbed';
  }
  if (lower.contains('زیرنویس') ||
      lower.contains('softsub') ||
      lower.contains('sub')) {
    return 'subbed';
  }
  if (lower.contains('زبان اصلی') || lower.contains('original')) {
    return 'original';
  }
  final cleaned = _cleanQualityTokens(name);
  return cleaned.isEmpty ? 'main' : cleaned;
}

String _movieCategoryTitle(String key, String sampleEpisodeName) {
  if (key.startsWith('dubbed')) {
    final cleaned = _cleanQualityTokens(sampleEpisodeName);
    if (cleaned.contains('دوبله') &&
        cleaned.length > 5 &&
        cleaned.length < 30) {
      return cleaned;
    }
    if (key.contains('-')) {
      final studio = key.split('-').last;
      return 'دوبله $studio';
    }
    return 'دوبله فارسی';
  }
  switch (key) {
    case 'subbed':
      final cleaned = _cleanQualityTokens(sampleEpisodeName);
      if (cleaned.contains('زیرنویس') &&
          cleaned.length > 8 &&
          cleaned.length < 30) {
        return cleaned;
      }
      return 'زیرنویس فارسی';
    case 'original':
      return 'زبان اصلی';
    case 'main':
      return 'نسخه اصلی';
    default:
      return key;
  }
}

String _cleanQualityTokens(String input) {
  var value = _latinDigits(input);
  value = value.replaceAll(
    RegExp(r'\d{3,4}\s*[pP]\b', caseSensitive: false),
    ' ',
  );
  value = value.replaceAll(
    RegExp(r'\b(4k|uhd|fhd|hd|sd)\b', caseSensitive: false),
    ' ',
  );
  value = value.replaceAll(RegExp(r'کیفیت\s*:?\s*\d{3,4}'), ' ');
  value = value.replaceAll(RegExp(r'\d{3,4}\s*:?\s*کیفیت'), ' ');
  value = value.replaceAll(RegExp(r'فول\s*اچ\s*دی|اچ\s*دی'), ' ');
  value = value.replaceAll(RegExp(r'[-_·•/|:؛،,\(\)\[\]]+'), ' ');
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _seasonKey(String input, int fallbackIndex) {
  var value = _latinDigits(input).toLowerCase();
  if (isTrailerLabel(value)) return 'trailer';

  final numMatch =
      RegExp(r'(?:فصل|season|s)\s*(\d+)').firstMatch(value) ??
      RegExp(r'^\s*(\d+)').firstMatch(value);
  final seasonNum = numMatch != null ? int.tryParse(numMatch.group(1)!) : null;

  var cleaned = _cleanQualityTokens(value).toLowerCase();
  if (seasonNum != null) {
    cleaned = cleaned
        .replaceAll(RegExp(r'(?:فصل|season|s)\s*' + seasonNum.toString()), ' ')
        .replaceAll(RegExp(r'^\s*' + seasonNum.toString()), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  if (seasonNum != null) {
    return cleaned.isEmpty ? 'season-$seasonNum' : 'season-$seasonNum-$cleaned';
  }
  return cleaned.isEmpty ? 'season-${fallbackIndex + 1}' : 'season-$cleaned';
}

String _episodeKey(String input, int fallbackIndex) {
  final value = _latinDigits(input).toLowerCase();
  if (isTrailerLabel(value)) {
    return 'trailer-${fallbackIndex + 1}';
  }
  final match =
      RegExp(r'(?:قسمت|episode|ep|part)\s*(\d+)').firstMatch(value) ??
      RegExp(r'^\*?\s*(\d+)\b').firstMatch(value) ??
      RegExp(r'\b(\d+)\b').firstMatch(value);
  if (match != null) return 'episode-${int.parse(match.group(1)!)}';
  final text = value
      .replaceAll(RegExp(r'قسمت|episode|part'), ' ')
      .replaceAll(RegExp(r'[^a-z\u0600-\u06ff]+'), ' ')
      .trim();
  return text.isEmpty ? 'episode-${fallbackIndex + 1}' : 'episode-$text';
}

String _seasonDisplayName(String key, String original) {
  if (key == 'trailer') return 'تیزرها';

  var cleaned = _cleanQualityTokens(original);

  final bareNumMatch = RegExp(
    r'^(\d+)\s*(.*)$',
  ).firstMatch(_latinDigits(cleaned));
  if (bareNumMatch != null && !cleaned.startsWith('فصل')) {
    final num = bareNumMatch.group(1)!;
    final rest = bareNumMatch.group(2)!.trim();
    return rest.isEmpty ? 'فصل $num' : 'فصل $num $rest';
  }

  return cleaned.isEmpty ? 'فصل' : cleaned;
}

String _latinDigits(String value) {
  const source = '۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩';
  var result = value;
  for (var index = 0; index < source.length; index++) {
    result = result.replaceAll(source[index], '${index % 10}');
  }
  return result;
}

int _naturalCompare(String left, String right) {
  final leftNumbers = RegExp(r'\d+')
      .allMatches(_latinDigits(left))
      .map((match) => int.parse(match.group(0)!))
      .toList();
  final rightNumbers = RegExp(r'\d+')
      .allMatches(_latinDigits(right))
      .map((match) => int.parse(match.group(0)!))
      .toList();
  for (var i = 0; i < leftNumbers.length && i < rightNumbers.length; i++) {
    final result = leftNumbers[i].compareTo(rightNumbers[i]);
    if (result != 0) return result;
  }
  return left.toLowerCase().compareTo(right.toLowerCase());
}
