import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/episode_catalog.dart';
import 'package:mbnmovie/models/movie_content.dart';

void main() {
  test('quality seasons collapse into logical seasons and episodes', () {
    const content = MovieContent(
      id: 'show',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [Colors.black],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'a',
          name: '1 480p زیرنویس',
          episodes: [
            MovieEpisode(id: '1a', name: '*1', fileUrl: '480-1'),
            MovieEpisode(id: '2a', name: '*2', fileUrl: '480-2'),
          ],
        ),
        MovieSeason(
          id: 'b',
          name: '۱ 720P زیرنویس',
          episodes: [
            MovieEpisode(id: '1b', name: '*۱', fileUrl: '720-1'),
            MovieEpisode(id: '2b', name: '*۲', fileUrl: '720-2'),
          ],
        ),
        MovieSeason(
          id: 'c',
          name: '1 1080p زیرنویس',
          episodes: [
            MovieEpisode(id: '1c', name: '*1', fileUrl: '1080-1'),
            MovieEpisode(id: '2c', name: '*2', fileUrl: '1080-2'),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    expect(catalog.seasons, hasLength(1));
    expect(catalog.seasons.single.name, 'فصل 1 زیرنویس');
    expect(catalog.seasons.single.episodes, hasLength(2));
    expect(catalog.seasons.single.episodes.first.variants, hasLength(3));
    expect(catalog.qualities, ['1080p', '720p', '480p']);
    expect(recommendedEpisodeQuality(catalog.qualities), '720p');
    expect(
      catalog.seasons.single.episodes.first.variantFor('1080p').episode.fileUrl,
      '1080-1',
    );
  });

  test('movie qualities become one playable movie', () {
    const content = MovieContent(
      id: 'movie',
      title: 'Movie',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.movie,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'movie',
          name: 'کیفیت‌های پخش',
          episodes: [
            MovieEpisode(id: '1', name: '720P', fileUrl: 'movie-720'),
            MovieEpisode(id: '2', name: '1080P', fileUrl: 'movie-1080'),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    expect(catalog.episodes, hasLength(1));
    expect(catalog.episodes.single.variants, hasLength(2));
  });

  test('trailer without a quality label does not pollute season qualities', () {
    const content = MovieContent(
      id: 'show-with-trailer',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'trailer',
          name: 'تیزر',
          episodes: [MovieEpisode(id: 't1', name: 'تیزر', fileUrl: 'trailer')],
        ),
        MovieSeason(
          id: '720',
          name: 'فصل 1 زیرنویس 720p',
          episodes: [MovieEpisode(id: 'e1', name: 'قسمت 1', fileUrl: '720-1')],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    final season = catalog.seasons.singleWhere(
      (item) => item.name == 'فصل 1 زیرنویس',
    );
    expect(season.qualities, ['720p']);
    expect(
      catalog.seasons.singleWhere((item) => item.name == 'تیزرها').qualities,
      ['بدون برچسب کیفیت'],
    );
  });

  test('trailer season hides the unknown quality chip', () {
    const content = MovieContent(
      id: 'show-with-trailer',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'trailer',
          name: 'تیزر',
          episodes: [MovieEpisode(id: 't1', name: 'تیزر', fileUrl: 'trailer')],
        ),
        MovieSeason(
          id: '720',
          name: 'فصل 1 زیرنویس 720p',
          episodes: [MovieEpisode(id: 'e1', name: 'قسمت 1', fileUrl: '720-1')],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    final trailerSeason = catalog.seasons.singleWhere(
      (item) => item.name == 'تیزرها',
    );
    expect(trailerSeason.isTrailerSeason, isTrue);
    // به‌جای نمایش «بدون برچسب کیفیت»، ردیف کیفیت مخفی می‌شود.
    expect(trailerSeason.displayQualities, isEmpty);
    final trailerGroup = trailerSeason.episodes.single;
    expect(trailerGroup.isTrailer, isTrue);
    expect(isUnknownQuality(trailerGroup.variants.single.quality), isTrue);
  });

  test('movie trailer does not pollute the movie quality list', () {
    const content = MovieContent(
      id: 'movie-with-trailer',
      title: 'Movie',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.movie,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'movie',
          name: 'کیفیت‌های پخش',
          episodes: [
            MovieEpisode(id: '1', name: '720P', fileUrl: 'movie-720'),
            MovieEpisode(id: '2', name: '1080P', fileUrl: 'movie-1080'),
            MovieEpisode(id: '3', name: '480p', fileUrl: 'movie-480'),
            MovieEpisode(id: 't', name: 'تیزر', fileUrl: 'movie-trailer'),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    final season = catalog.seasons.single;
    expect(season.name, 'فیلم');
    // چیپ «بدون برچسب کیفیت» نباید بین کیفیت‌های فیلم دیده شود.
    expect(season.displayQualities, ['1080p', '720p', '480p']);
    expect(catalog.qualities, ['1080p', '720p', '480p']);
    expect(season.episodes, hasLength(2));
    final main = season.episodes.firstWhere(
      (group) => group.id == 'logical:movie:main',
    );
    expect(main.name, 'پخش فیلم');
    expect(main.variants, hasLength(3));
    final trailer = season.episodes.firstWhere((group) => group.isTrailer);
    expect(trailer.variants, hasLength(1));
    expect(isUnknownQuality(trailer.variants.single.quality), isTrue);
  });

  test('movie download plan lists all-qualities plus each quality', () {
    const content = MovieContent(
      id: 'movie-dl',
      title: 'Movie',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.movie,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'movie',
          name: 'کیفیت‌های پخش',
          episodes: [
            MovieEpisode(id: '1', name: '720P', fileUrl: 'movie-720'),
            MovieEpisode(id: '2', name: '1080P', fileUrl: 'movie-1080'),
            MovieEpisode(id: 't', name: 'تیزر', fileUrl: 'movie-trailer'),
          ],
        ),
      ],
    );

    final plan = normalDownloadPlan(content);
    expect(plan.isMovie, isTrue);
    expect(plan.movieAll, isNotNull);
    expect(plan.movieAll!.label, 'دانلود همه 2 کیفیت');
    expect(plan.movieAll!.episodes, hasLength(2));
    expect(
      plan.batches.map((batch) => batch.label),
      ['دانلود کیفیت 1080p', 'دانلود کیفیت 720p'],
    );
    for (final batch in plan.batches) {
      expect(batch.episodes, hasLength(1));
      expect(batch.episodes.single.fileUrl, isNot('movie-trailer'));
    }
  });

  test('series download plan batches every episode of each quality', () {
    const content = MovieContent(
      id: 'show-dl',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'a',
          name: '1 480p زیرنویس',
          episodes: [
            MovieEpisode(id: '1a', name: '*1', fileUrl: '480-1'),
            MovieEpisode(id: '2a', name: '*2', fileUrl: '480-2'),
          ],
        ),
        MovieSeason(
          id: 'b',
          name: '۱ 720P زیرنویس',
          episodes: [
            MovieEpisode(id: '1b', name: '*۱', fileUrl: '720-1'),
            MovieEpisode(id: '2b', name: '*۲', fileUrl: '720-2'),
          ],
        ),
      ],
    );

    final plan = normalDownloadPlan(content);
    expect(plan.isMovie, isFalse);
    expect(plan.movieAll, isNull);
    // هر کیفیت جداگانه با همهٔ قسمت‌هایش؛ بدون بستهٔ چندکیفیتی.
    expect(plan.batches, hasLength(2));
    final byLabel = {for (final batch in plan.batches) batch.label: batch};
    expect(byLabel.keys.any((label) => label.contains('720p')), isTrue);
    expect(byLabel.keys.any((label) => label.contains('480p')), isTrue);
    for (final batch in plan.batches) {
      expect(batch.episodes, hasLength(2));
    }
  });

  test('bare and starred episode numbers display as قسمت N', () {
    // قالب واقعی API پسوند ستاره است («4*») که در رابط راست‌به‌چپ «*4»
    // دیده می‌شود؛ هر دو جهت پشتیبانی می‌شود.
    const content = MovieContent(
      id: 'starred',
      title: 'Show',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 's1080',
          name: 'فصل 1 زیرنویس 1080p',
          episodes: [
            MovieEpisode(id: 'e3', name: '3', fileUrl: 'u3'),
            MovieEpisode(id: 'e4', name: '4*', fileUrl: 'u4'),
            MovieEpisode(id: 'e5', name: '*5', fileUrl: 'u5'),
            MovieEpisode(id: 'e6', name: 'قسمت 6', fileUrl: 'u6'),
            MovieEpisode(id: 'e7', name: 'قسمت اول', fileUrl: 'u7'),
          ],
        ),
      ],
    );

    expect(episodeDisplayName('3'), 'قسمت 3');
    expect(episodeDisplayName('4*'), 'قسمت 4');
    expect(episodeDisplayName('*5'), 'قسمت 5');
    expect(episodeDisplayName('* 5'), 'قسمت 5');
    expect(episodeDisplayName('قسمت 6'), 'قسمت 6');
    expect(episodeDisplayName('قسمت اول'), 'قسمت اول');
    expect(episodeDisplayName('تیزر'), 'تیزر');
    expect(episodeDisplayName('  '), 'قسمت');

    final catalog = EpisodeCatalog.from(content);
    final names = catalog.seasons.single.episodes
        .map((group) => group.name)
        .toSet();
    expect(names, {'قسمت 3', 'قسمت 4', 'قسمت 5', 'قسمت 6', 'قسمت اول'});
    // ستاره هیچ‌جا در نام نمایشی نمی‌ماند.
    expect(names.any((name) => name.contains('*')), isFalse);
  });

  test('trailer helpers detect fa/en labels and server suffixes', () {
    expect(isTrailerLabel('تیزر'), isTrue);
    expect(isTrailerLabel('Trailer EP1'), isTrue);
    expect(isTrailerLabel('قسمت 1'), isFalse);
    expect(isUnknownQuality('بدون برچسب کیفیت'), isTrue);
    expect(isUnknownQuality('بدون برچسب کیفیت · سرور 2'), isTrue);
    expect(isUnknownQuality('720p'), isFalse);
    expect(qualityDisplayLabel('بدون برچسب کیفیت'), 'پخش');
    expect(
      qualityDisplayLabel('بدون برچسب کیفیت • سرور ۲'),
      'سرور ۲',
    );
  });

  test('raw file sizes display as compact MB/GB labels', () {
    expect(formatFileSize(''), '');
    expect(formatFileSize('714'), '714MB');
    expect(formatFileSize('55'), '55MB');
    expect(formatFileSize('1.2 GB'), '1.2GB');
    expect(formatFileSize('550mb'), '550MB');
    expect(formatFileSize('700KB'), '700KB');
    expect(formatFileSize('1610612736'), '1.5GB');
    expect(formatFileSize('125829120'), '120MB');
    expect(formatFileSize('۷۱۴'), '714MB');
    expect(formatFileSize('0'), '');
    expect(formatFileSize('437 مگابایت'), '437MB');
    expect(formatFileSize('1074 مگابایت'), '1074MB');
    expect(formatFileSize('1.5 گیگابایت'), '1.5GB');
    expect(formatFileSize('700 کیلوبایت'), '700KB');
  });

  test('Persian catalog quality labels resolve to pixel buckets', () {
    expect(episodeQuality('', 'قسمت 1 - کیفیت : 480'), '480p');
    expect(episodeQuality('کیفیت‌های پخش', 'قسمت 2 - کیفیت 720'), '720p');
    expect(episodeQuality('', '720 کیفیت'), '720p');
    expect(episodeQuality('', 'نسخه 720p دوبله'), '720p');
    expect(episodeQuality('کیفیت‌های پخش', 'پخش فیلم'), unknownQualityLabel);
  });

  test('distinct season variants (dub, sub, black & white) are not merged into servers', () {
    const content = MovieContent(
      id: 'show-variants',
      title: 'Show Variants',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 's1-dub',
          name: 'فصل 1 دوبله',
          episodes: [
            MovieEpisode(id: '1d', name: 'قسمت 1 - کیفیت : 720', fileUrl: 'dub-1-720'),
            MovieEpisode(id: '2d', name: 'قسمت 2 - کیفیت : 720', fileUrl: 'dub-2-720'),
          ],
        ),
        MovieSeason(
          id: 's1-sub',
          name: 'فصل 1 زیرنویس',
          episodes: [
            MovieEpisode(id: '1s', name: 'قسمت 1 - کیفیت : 720', fileUrl: 'sub-1-720'),
            MovieEpisode(id: '2s', name: 'قسمت 2 - کیفیت : 720', fileUrl: 'sub-2-720'),
          ],
        ),
        MovieSeason(
          id: 's1-bw',
          name: 'فصل 1 دوبله سیاه و سفید',
          episodes: [
            MovieEpisode(id: '1bw', name: 'قسمت 1 - کیفیت : 720', fileUrl: 'bw-1-720'),
            MovieEpisode(id: '2bw', name: 'قسمت 2 - کیفیت : 720', fileUrl: 'bw-2-720'),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    expect(catalog.seasons, hasLength(3));
    expect(
      catalog.seasons.map((s) => s.name).toList(),
      ['فصل 1 دوبله', 'فصل 1 دوبله سیاه و سفید', 'فصل 1 زیرنویس'],
    );
    for (final season in catalog.seasons) {
      expect(season.episodes, hasLength(2));
      expect(season.episodes.map((e) => e.name).toList(), ['قسمت 1', 'قسمت 2']);
      expect(season.episodes.first.variants.single.quality, '720p');
    }
  });

  test('episodeDisplayName normalizes raw titles with qualities to clean episode labels', () {
    expect(episodeDisplayName('قسمت 1 - کیفیت : 480'), 'قسمت 1');
    expect(episodeDisplayName('قسمت ۱ - کیفیت ۷۲۰'), 'قسمت 1');
    expect(episodeDisplayName('1 - کیفیت 1080'), 'قسمت 1');
    expect(episodeDisplayName('*1'), 'قسمت 1');
    expect(episodeDisplayName('قسمت اول'), 'قسمت اول');
    expect(episodeDisplayName('Episode 5'), 'قسمت 5');
    expect(episodeDisplayName('Ep 3 - 720p'), 'قسمت 3');
  });

  test('pure seasons without variant labels collapse into bare season', () {
    const content = MovieContent(
      id: 'show-pure',
      title: 'Show Pure',
      subtitle: '',
      description: '',
      year: 2026,
      rating: 8,
      kind: ContentKind.series,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 's1-1080',
          name: 'فصل 1 1080p',
          episodes: [
            MovieEpisode(id: '1a', name: 'قسمت 1', fileUrl: 's1-1080-1'),
          ],
        ),
        MovieSeason(
          id: 's1-720',
          name: 'فصل 1 720p',
          episodes: [
            MovieEpisode(id: '1b', name: 'قسمت 1', fileUrl: 's1-720-1'),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);
    expect(catalog.seasons, hasLength(1));
    expect(catalog.seasons.single.name, 'فصل 1');
    expect(catalog.seasons.single.episodes.first.variants, hasLength(2));
  });

  test('movie with dub and sub variants separates into clean categories without server labels', () {
    const content = MovieContent(
      id: 'kung-fu-panda-4',
      title: 'پاندای کونگ فو کار 4',
      subtitle: '',
      description: '',
      year: 2024,
      rating: 7.5,
      kind: ContentKind.movie,
      colors: [],
      genres: [],
      seasons: [
        MovieSeason(
          id: 'movie',
          name: 'کیفیت‌های پخش',
          episodes: [
            MovieEpisode(
              id: 'ep-sub-1080-hd',
              name: 'کیفیت 1080 زیرنویس hd',
              fileUrl: 'https://example.com/sub-1080-hd.mp4',
              fileSize: '4849 MB',
            ),
            MovieEpisode(
              id: 'ep-sub-1080',
              name: 'کیفیت 1080 زیرنویس',
              fileUrl: 'https://example.com/sub-1080.mp4',
              fileSize: '1765 MB',
            ),
            MovieEpisode(
              id: 'ep-sub-720',
              name: 'کیفیت 720 زیرنویس',
              fileUrl: 'https://example.com/sub-720.mp4',
              fileSize: '859 MB',
            ),
            MovieEpisode(
              id: 'ep-dub-480',
              name: 'کیفیت 480 دوبله',
              fileUrl: 'https://example.com/dub-480.mp4',
              fileSize: '537 MB',
            ),
            MovieEpisode(
              id: 'ep-dub-720',
              name: 'کیفیت 720 دوبله',
              fileUrl: 'https://example.com/dub-720.mp4',
              fileSize: '987 MB',
            ),
            MovieEpisode(
              id: 'ep-dub-1080',
              name: 'کیفیت 1080 دوبله',
              fileUrl: 'https://example.com/dub-1080.mp4',
              fileSize: '1931 MB',
            ),
          ],
        ),
      ],
    );

    final catalog = EpisodeCatalog.from(content);

    // Should have 2 category seasons: Dubbed and Subbed
    expect(catalog.seasons, hasLength(2));
    expect(catalog.seasons[0].name, 'دوبله فارسی');
    expect(catalog.seasons[1].name, 'زیرنویس فارسی');

    // Dubbed qualities
    expect(catalog.seasons[0].displayQualities, ['1080p', '720p', '480p']);

    // Subbed qualities with 1080p HD ranked first
    expect(catalog.seasons[1].displayQualities, ['1080p HD', '1080p', '720p']);

    // Ensure NO variant has 'سرور' in its quality label
    for (final season in catalog.seasons) {
      for (final episodeGroup in season.episodes) {
        for (final variant in episodeGroup.variants) {
          expect(variant.quality.contains('سرور'), isFalse,
              reason: 'Quality "${variant.quality}" should not contain "سرور"');
        }
      }
    }

    // Check normalDownloadPlan
    final plan = normalDownloadPlan(content);
    expect(plan.isMovie, isTrue);
    expect(plan.batches, hasLength(6));
    expect(plan.movieAll?.label, 'دانلود همه 6 نسخه');
  });
}

