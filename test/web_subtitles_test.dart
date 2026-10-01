import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/web_subtitles.dart';

void main() {
  test('Persian SRT, overlapping cues, delay and scale', () {
    final doc = WebSubtitleDocument.parse(
      '1\n00:00:01,000 --> 00:00:03,000\n<b>سلام</b>\n\n2\n00:00:02,000 --> 00:00:04,000\nدوم',
    );
    expect(doc.at(const Duration(milliseconds: 2500)), ['سلام', 'دوم']);
    expect(doc.at(const Duration(seconds: 3), delay: 1, scale: 2), ['سلام']);
    expect(
      doc.vtt(delay: 1, scale: 2),
      contains('00:00:03.000 --> 00:00:07.000'),
    );
  });
  test('WebVTT settings and ASS commas and styling', () {
    final vtt = WebSubtitleDocument.parse(
      'WEBVTT\n\n00:00:01.000 --> 00:00:02.000 align:start\nمتن',
    );
    expect(vtt.at(const Duration(seconds: 1)), ['متن']);
    final ass = WebSubtitleDocument.parse(
      r'Dialogue: 0,0:00:01.00,0:00:04.50,Default,,0,0,0,,{\b1}سلام, جهان\Nخط دوم',
    );
    expect(ass.at(const Duration(seconds: 2)), ['سلام, جهان\nخط دوم']);
    expect(() => WebSubtitleDocument.parse('broken'), throwsFormatException);
  });
  test(
    'long overlapping cue and backward seeking preserve every active line',
    () {
      final doc = WebSubtitleDocument([
        const WebSubtitleCue(0, 100, 'long'),
        const WebSubtitleCue(1, 2, 'short'),
        const WebSubtitleCue(50, 51, 'middle'),
      ]);
      expect(doc.at(const Duration(seconds: 80)), ['long']);
      expect(doc.at(const Duration(milliseconds: 1500)), ['long', 'short']);
      expect(doc.at(const Duration(seconds: 101)), isEmpty);
    },
  );
}
