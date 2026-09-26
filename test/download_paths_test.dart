import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/download_paths.dart';
import 'package:mbnmovie/models/movie_content.dart';

void main() {
  test(
    'all new folder components are ASCII and preserve quality identities',
    () {
      const content = MovieContent(
        id: '42',
        title: 'عنوان فارسی',
        alternateTitles: ['English Title'],
        subtitle: '',
        description: '',
        year: 2026,
        rating: 0,
        kind: ContentKind.series,
        colors: [],
        genres: [],
      );
      const first = MovieSeason(
        id: '720',
        name: 'فصل ۱ زیرنویس 720p',
        episodes: [],
      );
      const second = MovieSeason(
        id: '1080',
        name: 'فصل ۱ زیرنویس 1080p',
        episodes: [],
      );
      final parts = downloadFolderParts(content, first);
      expect(parts.first, 'Series');
      expect(parts[1], startsWith('English Title (2026)'));
      expect(parts.last, contains('720p'));
      expect(parts.last, isNot(downloadFolderParts(content, second).last));
      for (final part in parts) {
        expect(RegExp(r'^[\x20-\x7e]+$').hasMatch(part), isTrue);
        expect(part.contains('/'), isFalse);
      }
      expect(englishDownloadFolder('فارسی', 'Title'), 'Title');
      expect(englishDownloadFolder('۱۲۳', 'Season'), '123');
    },
  );
  test('safe Persian paths, no traversal or reserved Windows filenames', () {
    expect(safeDownloadComponent('فصل اول'), 'فصل اول');
    for (final text in ['..', '', 'CON', 'NUL.txt', 'a/b:c*?', 'name. ']) {
      final safe = safeDownloadComponent(text);
      expect(safe, isNotEmpty);
      expect(safe.contains('/'), isFalse);
      expect(safe.contains(':'), isFalse);
      expect(safe.endsWith('.'), isFalse);
      expect(safe, isNot('..'));
    }
    expect(safeDownloadComponent('CON'), '_CON');
  });
  test('quality/season identities do not overwrite each other', () {
    final first = downloadIdentity('movie', '720p', '1');
    final second = downloadIdentity('movie', '1080p', '1');
    expect(first, isNot(second));
    expect(first, downloadIdentity('movie', '720p', '1'));
    expect(
      episodeDownloadFilename(
        const MovieEpisode(
          id: '1',
          name: 'قسمت/1',
          fileUrl: 'https://example.org/file.mkv?token=abc',
        ),
        first,
      ),
      endsWith('.mkv'),
    );
    expect(
      episodeDownloadFilename(
        const MovieEpisode(
          id: '1',
          name: '1',
          fileUrl: 'https://example.org/',
          fileType: '../../bad',
        ),
        first,
      ),
      endsWith('.mp4'),
    );
  });
}
