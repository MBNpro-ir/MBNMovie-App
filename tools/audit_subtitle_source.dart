// Run with Dart from this app: tools/audit_subtitle_source.dart <extracted.srt>
import 'dart:convert';
import 'dart:io';
import 'package:mbnmovie/core/subtitle_bidi.dart';
import 'package:mbnmovie/core/web_subtitles.dart';
import 'package:mbnmovie/core/subtitle_unicode.dart';

void main(List<String> args) {
  final source = File(args.single).readAsStringSync();
  final watch = Stopwatch()..start();
  final document = WebSubtitleDocument.parse(source);
  final parseMicros = watch.elapsedMicroseconds;
  final raw = source
      .replaceAll('\r', '')
      .split(RegExp(r'\n\s*\n'))
      .map((block) {
        final lines = block.split('\n'),
            index = block.split('\n').indexWhere((s) => s.contains('-->'));
        return lines
            .skip(index + 1)
            .join('\n')
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
      })
      .where((s) => s.isNotEmpty)
      .toList();
  if (raw.length != document.cues.length) throw StateError('Cue count changed');
  final tracker = SubtitleTextNormalizer();
  var compared = 0;
  for (var i = 0; i < raw.length; i++) {
    final canonical = document.cues[i].text;
    List<int> characters(String s) =>
        s
            .replaceAll('ي', 'ی')
            .replaceAll('ك', 'ک')
            .replaceAll(
              RegExp(
                r'[\s\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
                unicode: true,
              ),
              '',
            )
            .runes
            .map((r) {
              final mirror = subtitleBidiMirrors[r] ?? r;
              return r < mirror ? r : mirror;
            })
            .toList()
          ..sort();
    final before = characters(raw[i]);
    final after = characters(canonical);
    if (before.join(',') != after.join(',')) {
      throw StateError('Text loss in cue ${i + 1}');
    }
    final native = tracker.normalize([raw[i]], track: (1, 'fa')).single;
    if (tracker.sourceOrder == SubtitleSourceOrder.legacyLtr) {
      if (native != canonical) {
        throw StateError('Native/web mismatch in cue ${i + 1}');
      }
      compared++;
    }
  }
  final vtt = document.vtt();
  final again = WebSubtitleDocument.parse(vtt);
  String plain(String s) => s.replaceAll(
    RegExp(r'[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]'),
    '',
  );
  for (var i = 0; i < again.cues.length; i++) {
    if (plain(again.cues[i].text) != plain(document.cues[i].text)) {
      throw StateError('VTT roundtrip changed cue ${i + 1}');
    }
  }
  watch.reset();
  for (var i = 0; i < 10000; i++) {
    tracker.normalize([raw.last], track: (1, 'fa'));
  }
  stdout.writeln(
    jsonEncode({
      'cues': document.cues.length,
      'sourceOrder': document.sourceOrder.name,
      'noTextLoss': true,
      'nativeWebCompared': compared,
      'vttRoundtrip': true,
      'parseMs': parseMicros / 1000,
      'cached10000CuesMs': watch.elapsedMicroseconds / 1000,
      'samples': {
        for (final index in [3, 74, 126, 148, 309, 458, 666])
          '${index + 1}': plain(document.cues[index].text),
      },
    }),
  );
}
