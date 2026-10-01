import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/episode_catalog.dart';
import 'package:mbnmovie/models/movie_content.dart';

void main() {
  test(
    'resume restores raw episode identity, quality variants and next episode',
    () {
      final content = MovieContent(
        id: 'title',
        title: 'Title',
        subtitle: '',
        description: '',
        year: 0,
        rating: 0,
        kind: ContentKind.series,
        colors: [],
        genres: [],
        seasons: [
          MovieSeason(
            id: '480',
            name: 'Season 1 480p',
            episodes: [
              MovieEpisode(
                id: 'raw1',
                name: '1',
                fileUrl: 'https://cdn/1-480.mp4',
              ),
              MovieEpisode(
                id: 'raw2',
                name: '2',
                fileUrl: 'https://cdn/2-480.mp4',
              ),
            ],
          ),
          MovieSeason(
            id: '720',
            name: 'Season 1 720p',
            episodes: [
              MovieEpisode(
                id: 'hd1',
                name: '1',
                fileUrl: 'https://cdn/1-720.mp4',
              ),
              MovieEpisode(
                id: 'hd2',
                name: '2',
                fileUrl: 'https://cdn/2-720.mp4',
              ),
            ],
          ),
        ],
      );
      final catalog = EpisodeCatalog.from(content);
      final group = catalog.episodes.first;
      final resumed = catalog.resumeVariant(
        episodeId: group.id,
        fileUrl: 'https://cdn/1-720.mp4',
      )!;
      expect(resumed.episode.id, 'hd1');
      expect(catalog.groupFor(resumed.episode)!.variants.length, 2);
      expect(catalog.episodes.length, 2);
      expect(
        catalog
            .resumeVariant(
              episodeId: group.id,
              fileUrl: 'https://expired/link',
              preferredQuality: '480p',
            )!
            .episode
            .id,
        'raw1',
      );
      expect(
        catalog.resumeVariant(
          episodeId: 'removed',
          fileUrl: 'https://missing/link',
        ),
        isNull,
      );
    },
  );
}
