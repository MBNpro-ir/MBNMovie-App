import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/services/app_links.dart';

void main() {
  test('registry key is namespaced per app', () {
    expect(AppLinks.registryKey('MBNMovie'), r'HKCU\Software\MBN\Apps\MBNMovie');
    expect(AppLinks.registryKey('MBNime'), r'HKCU\Software\MBN\Apps\MBNime');
  });

  test('reg query output parses REG_SZ values', () {
    const output = '\r\nHKEY_CURRENT_USER\\Software\\MBN\\Apps\\MBNime\r\n'
        '    InstallDir    REG_SZ    D:\\Apps\\MBNime\r\n'
        '    Exe    REG_SZ    mbnime.exe\r\n';
    expect(
      AppLinks.parseRegQueryValue(output, 'InstallDir'),
      r'D:\Apps\MBNime',
    );
    expect(AppLinks.parseRegQueryValue(output, 'Missing'), isNull);
    expect(AppLinks.parseRegQueryValue('not-a-registry-dump', 'InstallDir'), isNull);
  });

  test('sibling metadata points at the anime app', () {
    expect(siblingAnime.androidPackage, 'com.mbn.ime');
    expect(siblingAnime.windowsExe, 'mbnime.exe');
    expect(
      siblingAnime.githubReleasesUrl,
      'https://github.com/MBNpro-ir/MBNime-App/releases/latest',
    );
  });
}
