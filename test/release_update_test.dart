import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/release_update.dart';

Map<String, dynamic> releaseJson({
  String version = '1.2.0',
  String platform = 'Windows-x64',
  String? digest,
  int size = 3,
}) => {
  'tag_name': 'v$version',
  'draft': false,
  'prerelease': false,
  'body': '✨ تغییرات فارسی',
  'assets': [
    {
      'name':
          'MBNMovie-$platform-$version.${platform == 'Windows-x64' ? 'zip' : 'apk'}',
      'state': 'uploaded',
      'size': size,
      'digest': digest ?? 'sha256:${'a' * 64}',
      'browser_download_url':
          'https://github.com/MBNpro-ir/MBNMovie-App/releases/download/v$version/MBNMovie-$platform-$version.${platform == 'Windows-x64' ? 'zip' : 'apk'}',
    },
  ],
};

void main() {
  test(
    'stable semantic version comparison, no prereleases or malformed tags',
    () {
      expect(
        AppVersion.parse('v1.10.0')!.compareTo(AppVersion.parse('1.9.9+12')!),
        greaterThan(0),
      );
      expect(
        AppVersion.parse('2.0.0')!.compareTo(AppVersion.parse('1.99.99')!),
        greaterThan(0),
      );
      for (final input in [
        'latest',
        'v1.2',
        '1.2.0-beta',
        '../1.2.0',
        '1.2.0\n',
      ]) {
        expect(AppVersion.parse(input), isNull);
      }
    },
  );
  test(
    'selects exact platform, requires digest, rejects draft / untrusted URL',
    () {
      ReleaseUpdate? parse(Map<String, dynamic> data) =>
          ReleaseUpdate.fromGitHub(
            data,
            repository: 'MBNpro-ir/MBNMovie-App',
            platform: 'Windows-x64',
          );
      expect(parse(releaseJson())?.notes, '✨ تغییرات فارسی');
      expect(parse(releaseJson(platform: 'Android-arm64-v8a')), isNull);
      expect(parse({...releaseJson(), 'draft': true}), isNull);
      expect(parse({...releaseJson(), 'prerelease': true}), isNull);
      expect(parse(releaseJson(digest: 'sha256:bad')), isNull);
      expect(parse(releaseJson(size: 0)), isNull);
      for (final url in [
        'http://github.com/foo',
        'https://evil.example/file.zip',
        'https://github.com/other/repo/file.zip',
      ]) {
        final data = releaseJson();
        (data['assets'] as List).first['browser_download_url'] = url;
        expect(parse(data), isNull);
      }
    },
  );
  test(
    'zip traversal, absolute paths, ADS and unsafe Windows names rejected',
    () {
      expect(
        safeBundlePath('MBNMovie/data/flutter_assets/a.txt'),
        'data/flutter_assets/a.txt',
      );
      expect(safeBundlePath(r'MBNMovie\data\a.txt'), 'data/a.txt');
      for (final path in [
        '../mbnmovie.exe',
        '/MBNMovie/mbnmovie.exe',
        'MBNMovie/../outside',
        'MBNMovie/C:/x',
        'MBNMovie/file:stream',
        'MBNMovie/a.',
        'MBNMovie/a ',
        'MBNMovie/a\u0000.txt',
        'MBNMovie/a?.txt',
        'MBNMovie/data//app.so',
        'MBNMovie/CON.txt',
        'MBNMovie/data/aux',
        'MBNMovie/COM1',
      ]) {
        expect(() => safeBundlePath(path), throwsFormatException, reason: path);
      }
    },
  );
}
