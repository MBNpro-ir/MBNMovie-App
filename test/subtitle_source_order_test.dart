import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/subtitle_bidi.dart';
import 'package:mbnmovie/core/web_subtitles.dart';

String visible(String value) =>
    value.replaceAll(RegExp(r'[\u200E\u200F\u2066-\u2069]'), '');

const samples = <String, String>{
  'نوبت منه -': '- نوبت منه',
  '،شرمنده، چنین اجازه ای نداری -': '- شرمنده، چنین اجازه ای نداری،',
  'دکتر "وبر" دیگه کیه؟ -': '- دکتر "وبر" دیگه کیه؟',
  '،برجسته است U موج': 'موج U برجسته است،',
  '،برعکس نشده T موج': 'موج T برعکس نشده،',
  '.عادیه Q موج': 'موج Q عادیه.',
  '.باشه MS می تونه': 'می تونه MS باشه.',
  '.اسکن ممکن نیست CT و MRI': 'MRI و CT اسکن ممکن نیست.',
  'رو MS اقلاً اینطوری': 'اقلاً اینطوری MS رو',
  'بگیری؟ MRI': 'MRI بگیری؟',
  '.رو تشخیص بدی MS': 'MS رو تشخیص بدی.',
  'باشه، رگ های خونی واکنش بیشتری MS اگر':
      'اگر MS باشه، رگ های خونی واکنش بیشتری',
  '؟MS -': '- MS؟',
  '.پیچیده است MS ،نه -': '- نه، MS پیچیده است.',
  '.G نه M ایمنوگلوبولین': 'ایمنوگلوبولین M نه G.',
  'ها رو برداشتی؟ LSD تو': 'تو LSD ها رو برداشتی؟',
  'روی LSD چطوره به این دلیل که': 'چطوره به این دلیل که LSD روی',
  '،نهایتاً 12 ساعت می مونه LSD بهش گفتم که اثر':
      'بهش گفتم که اثر LSD نهایتاً 12 ساعت می مونه،',
  '،آدام"، داری زیادی تند می ری"': '"آدام"، داری زیادی تند می ری،',
  '"سخنرانی دکتر "وبر -': '- سخنرانی دکتر "وبر"',
  '(بخش های مختلف منحنی ضربان قلب)': '(بخش های مختلف منحنی ضربان قلب)',
  '.آماده است (MRI, CT) نتیجه': 'نتیجه (MRI, CT) آماده است.',
  '.آماده است [MRI (T1, T2)] نتیجه': 'نتیجه [MRI (T1, T2)] آماده است.',
  '.جایزۀ ۲۵٫۵ دلار است 😊': '😊 جایزۀ ۲۵٫۵ دلار است.',
};

void main() {
  test('real embedded track, including punctuation-free mixed cues', () {
    final doc = WebSubtitleDocument([
      for (final entry in samples.entries.indexed)
        WebSubtitleCue(entry.$1.toDouble(), entry.$1 + 1, entry.$2.key),
    ]);
    expect(doc.sourceOrder, SubtitleSourceOrder.legacyLtr);
    expect(doc.cues.map((c) => visible(c.text)), samples.values);
    // WebVTT/overlay consume canonical text exactly once.
    for (var i = 0; i < doc.cues.length; i++) {
      expect(doc.at(Duration(milliseconds: i * 1000 + 500)), [
        doc.cues[i].text,
      ]);
    }
    expect(
      doc.vtt(),
      contains(subtitleDisplayText([doc.cues[3].text], normalized: true)),
    );
  });

  test('same document policy applies to SRT, WebVTT and plain ASS', () {
    final raw = samples.keys.take(18).toList(),
        expected = samples.values.take(18).toList();
    final srt = [
      for (var i = 0; i < raw.length; i++)
        '${i + 1}\n00:00:${i.toString().padLeft(2, '0')},000 --> 00:00:${(i + 1).toString().padLeft(2, '0')},000\n<i>${raw[i]}</i>',
    ].join('\n\n');
    final ass = [
      for (var i = 0; i < raw.length; i++)
        'Dialogue: 0,0:00:$i.00,0:00:${i + 1}.00,Default,,0,0,0,,{\\i1}${raw[i]}',
    ].join('\n');
    for (final source in [srt, 'WEBVTT\n\n${srt.replaceAll(',', '.')}', ass]) {
      // Only timestamp separators change when converting SRT to VTT.
      final doc = WebSubtitleDocument.parse(source);
      expect(doc.cues.map((cue) => visible(cue.text)), expected);
    }
  });

  test(
    'healthy logical tracks, numbers, symbols, emoji and English are preserved',
    () {
      const healthy = [
        '- بیمار (MRI, CT) دارد.',
        'نسخه Windows 10 نصب شد.',
        'دما -12.5 C است.',
        'نتیجه [MRI (T1, T2)] آماده است.',
        'این جمله MS دارد و درست است.',
        'Hello, world!',
        'می\u200Cروم 👨‍👩‍👧‍👦؛ دمای ۲۵٫۵ درجه.',
      ];
      final doc = WebSubtitleDocument([
        for (final entry in healthy.indexed)
          WebSubtitleCue(entry.$1.toDouble(), entry.$1 + 1, entry.$2),
      ]);
      expect(doc.sourceOrder, isNot(SubtitleSourceOrder.legacyLtr));
      expect(doc.cues.map((cue) => visible(cue.text)), healthy);
    },
  );

  test(
    'native policy survives blank/repeated cues, resets for media and track',
    () {
      final normalizer = SubtitleTextNormalizer();
      for (final cue in samples.keys) {
        normalizer.normalize([cue, ''], track: (1, 'fa'));
      }
      expect(normalizer.sourceOrder, SubtitleSourceOrder.legacyLtr);
      for (final entry in samples.entries) {
        expect(
          visible(normalizer.normalize([entry.key], track: (1, 'fa')).single),
          entry.value,
        );
      }
      // Eviction and seeks cannot drop a detected source convention.
      for (var i = 0; i < 80; i++) {
        normalizer.normalize(['متن $i'], track: (1, 'fa'));
      }
      expect(
        visible(
          normalizer
              .normalize(['رو MS اقلاً اینطوری'], track: (1, 'fa'))
              .single,
        ),
        'اقلاً اینطوری MS رو',
      );
      const logical = 'بیمار MS دارد.';
      expect(
        visible(normalizer.normalize([logical], track: (1, 'en')).single),
        logical,
      );
      expect(normalizer.sourceOrder, SubtitleSourceOrder.automatic);
      expect(
        visible(normalizer.normalize([logical], track: (2, 'fa')).single),
        logical,
      );
    },
  );
}
