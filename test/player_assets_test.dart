import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const fonts = <String, String>{
    'NotoSansArabic': 'assets/fonts/NotoSansArabic-Variable.ttf',
    'NotoNaskhArabic': 'assets/fonts/NotoNaskhArabic-Variable.ttf',
    'MarkaziText': 'assets/fonts/MarkaziText-Variable.ttf',
  };

  test('Persian subtitle fonts are valid sfnt assets declared in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final entry in fonts.entries) {
      final bytes = File(entry.value).readAsBytesSync();
      expect(bytes.length, greaterThan(100000), reason: entry.value);
      expect(bytes.take(4), <int>[0, 1, 0, 0], reason: entry.value);
      expect(pubspec, contains('family: ${entry.key}'));
      expect(pubspec, contains('asset: ${entry.value}'));
    }
  });

  test('vendored media_kit contains the upstream hot restart guard', () {
    final source = File(
      'packages/media_kit/lib/src/player/native/player/real.dart',
    ).readAsStringSync();
    expect(source, contains('mpv_set_wakeup_callback'));
    expect(source, contains('nullptr, nullptr'));
  });
}
