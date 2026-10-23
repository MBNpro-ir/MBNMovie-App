import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/subtitle_bidi.dart';
import 'package:mbnmovie/core/web_subtitles.dart';
import 'package:mbnmovie/widgets/player_subtitle_text.dart';
import 'fixtures/subtitle_bidi_cases.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Vazirmatn');
    loader.addFont(rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf'));
    await loader.load();
  });

  test(
    'whole English phrases retain word order and normalization is stable',
    () {
      const source = 'سریال House of the Dragon و MRI/CT شماره 12.5 است.';
      final normalized = normalizePersianSubtitle(source);
      expect(normalized.replaceAll('\u200E', ''), source);
      expect(normalizePersianSubtitle(normalized), normalized);
      expect(normalizePersianSubtitle('می\u200Cروم'), 'می\u200Cروم');
      expect(
        normalizePersianSubtitle('\u202Dبیمار MRI دارد\u202C'),
        normalizePersianSubtitle('بیمار MRI دارد'),
      );
    },
  );

  test('restores legacy terminal marks without changing logical sources', () {
    const cases = {
      '،احتمالش زیاده مرخص بشه': 'احتمالش زیاده مرخص بشه،',
      '.باشه، خداحافظ': 'باشه، خداحافظ.',
      '؟نتیجه (MRI, CT) آماده است': 'نتیجه (MRI, CT) آماده است؟',
      '!بالاخره خوش اومدی -': '- بالاخره خوش اومدی!',
      '- !سلام': '- سلام!',
      '.«خداحافظ»': '«خداحافظ».',
    };
    for (final entry in cases.entries) {
      final expected = normalizePersianSubtitle(entry.value);
      expect(normalizePersianSubtitle(entry.key), expected);
      expect(normalizePersianSubtitle(expected), expected);
    }
    for (final source in [
      'باشه، خداحافظ.',
      '...ادامه دارد',
      '…ادامه دارد',
      '.NET برای ویندوز',
      '.5 ثانیه',
      '..:: زیرنویس فارسی ::..',
      'Hello, world!',
    ]) {
      expect(normalizePersianSubtitle(source).replaceAll('\u200E', ''), source);
    }
  });

  test('repairs visual-order Persian chunks around an English acronym', () {
    String legacy(String source) => normalizePersianSubtitle(
      source,
      sourceOrder: SubtitleSourceOrder.legacyLtr,
    ).replaceAll('\u200E', '');
    const source = 'هم روی صورتت هست KS و نهایتا یه زخم';
    const expected = 'و نهایتا یه زخم KS هم روی صورتت هست';
    expect(legacy(source), expected);
    expect(
      normalizePersianSubtitle(expected).replaceAll('\u200E', ''),
      expected,
    );

    const ana = '.برای "لوپوس" هم منفی بود ANA تست';
    expect(legacy(ana), 'تست ANA برای "لوپوس" هم منفی بود.');
    const mri = '.بگیرید MRI از خودش و خواهرش همین الان یه';
    expect(legacy(mri), 'از خودش و خواهرش همین الان یه MRI بگیرید.');
    const logical = 'این مشکل MRI و بعد حل شد';
    expect(normalizePersianSubtitle(logical).replaceAll('\u200E', ''), logical);
  });

  test('web SRT, VTT and plain ASS share the native bidi policy', () {
    const source = '،احتمالش زیاده مرخص بشه\n.باشه، خداحافظ';
    for (final document in [
      '1\n00:00:01,000 --> 00:00:03,000\n$source',
      'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\n$source',
      'Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,${source.replaceAll('\n', r'\N')}',
    ]) {
      final parsed = WebSubtitleDocument.parse(document);
      expect(parsed.at(const Duration(seconds: 2)), [
        normalizePersianSubtitle(source),
      ]);
      expect(parsed.vtt(), contains(subtitleDisplayText([source])));
    }
  });

  for (final sample in subtitleBidiCases) {
    for (final width in [760.0, 260.0]) {
      testWidgets('${sample.id}: glyph reading order at width $width', (
        tester,
      ) async {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: width,
                child: PlayerSubtitleText(
                  lines: [sample.canonicalText],
                  normalized: true,
                  style: const TextStyle(fontFamily: 'Vazirmatn', fontSize: 24),
                ),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText),
        );
        final text = paragraph.text.toPlainText();
        Rect box(String word) {
          final (start, end) = subtitleTokenRange(text, word);
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end),
            boxHeightStyle: ui.BoxHeightStyle.max,
          );
          expect(boxes, isNotEmpty);
          return boxes.first.toRect();
        }

        for (final (rtl, pairs) in [(false, sample.ltr), (true, sample.rtl)]) {
          for (final (first, second) in pairs) {
            final a = box(first), b = box(second);
            if ((a.top - b.top).abs() > 1) {
              expect(
                a.top,
                lessThan(b.top),
                reason: '$first before $second in ${sample.text}',
              );
            } else {
              expect(
                a.center.dx,
                rtl ? greaterThan(b.center.dx) : lessThan(b.center.dx),
                reason: '$first before $second in ${sample.text}',
              );
            }
          }
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final surroundingDirection in TextDirection.values) {
    testWidgets(
      'mixed glyph order ignores $surroundingDirection player layout',
      (tester) async {
        const lines = [
          '- سلام',
          '- بیمار (MRI) دارد.',
          'سریال House of the Dragon خوب است',
          'Hello world!',
        ];
        await tester.pumpWidget(
          Directionality(
            textDirection: surroundingDirection,
            child: const Center(
              child: SizedBox(
                width: 760,
                child: PlayerSubtitleText(
                  lines: lines,
                  style: TextStyle(fontFamily: 'Vazirmatn', fontSize: 24),
                ),
              ),
            ),
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byType(RichText),
        );
        final text = paragraph.text.toPlainText();
        double x(String word, [int offset = 0]) {
          final start = text.indexOf(word, offset);
          expect(start, greaterThanOrEqualTo(0));
          final boxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: start + word.length),
          );
          expect(boxes, isNotEmpty);
          return boxes.first.toRect().center.dx;
        }

        expect(x('-'), greaterThan(x('سلام')));
        expect(x('بیمار'), greaterThan(x('MRI')));
        expect(x('MRI'), greaterThan(x('دارد')));
        expect(x('M'), lessThan(x('R')));
        expect(x('R'), lessThan(x('I')));
        // RTL brackets are mirrored: logical opening is on the right.
        expect(x('('), greaterThan(x('MRI')));
        expect(x(')'), lessThan(x('MRI')));
        expect(x('سریال'), greaterThan(x('House')));
        expect(x('House'), lessThan(x('Dragon')));
        expect(x('Dragon'), greaterThan(x('خوب')));
        expect(x('Hello'), lessThan(x('world')));
        expect(x('!'), greaterThan(x('world')));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
