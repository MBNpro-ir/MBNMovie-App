import 'subtitle_order.dart';

// Plain subtitle rendering only. Original ASS keeps its authored layout.
final _rtlLetters = RegExp(
  r'[\u0590-\u05FF\u0620-\u064A\u066E-\u066F\u0671-\u06D3\u06D5\u06EE-\u06EF\u06FA-\u06FC\u0750-\u077F\u08A0-\u08C9\uFB1D-\uFDFF\uFE70-\uFEFC]',
);
final _directionControls = RegExp(
  r'[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
);
final _explicitDirection = RegExp(r'[\u061C\u200F\u202A-\u202E\u2066-\u2069]');
final _latinPhrase = RegExp(
  r"(?:[+-](?=[0-9]))?[A-Za-z0-9]+(?:[+./:_'\-][A-Za-z0-9]+)*(?:[ \t]+[A-Za-z0-9]+(?:[+./:_'\-][A-Za-z0-9]+)*)*(?:\+\+|#)?",
);
final _latinLetters = RegExp(r'[A-Za-z]');
final _delimitedText = RegExp(
  r'''"[^"\n]*"|'[^'\n]*'|«[^«»\n]*»|“[^“”\n]*”|‘[^‘’\n]*’|\([^()\n]*\)|\[[^\[\]\n]*\]|\{[^{}\n]*\}''',
);
final _terminalPunctuation = RegExp(r'[.!?,;:…]+[ \t]*$');
final _leadingMark = RegExp(r'^([ \t]*(?:[-–—][ \t]*)?)([.,،;؛!?؟]+)[ \t]*');
final _trailingDialogue = RegExp(r'[ \t]+([-–—])[ \t]*$');
final _openingDelimiters = RegExp(r'''^[ \t"'«“‘(\[{]*''');

enum SubtitleSourceOrder { automatic, logical, legacyLtr }

bool subtitleHasRtlLetters(String text) => _rtlLetters.hasMatch(text);

bool _legacyLine(String line) {
  if (!subtitleHasRtlLetters(line) || _explicitDirection.hasMatch(line)) {
    return false;
  }
  if (_trailingDialogue.hasMatch(line)) return true;
  final match = _leadingMark.firstMatch(line);
  if (match == null || match.group(2)!.contains('..')) return false;
  final content = line
      .substring(match.end)
      .replaceFirst(_openingDelimiters, '');
  // A leading .NET or .5 is not a displaced Persian sentence stop.
  return content.isNotEmpty && !RegExp(r'^\d|^NET\b').hasMatch(content);
}

bool _logicalLine(String line) =>
    subtitleHasRtlLetters(line) &&
    !_legacyLine(line) &&
    (_explicitDirection.hasMatch(line) ||
        RegExp(r'^\s*[-–—]\s|[.،؛]\s*$').hasMatch(line));

/// Source-level evidence matters: mixed text alone cannot reveal whether its
/// author stored logical RTL or LTR-player run order. Never guess from Persian
/// words, film titles, acronyms, or the user's UI language.
SubtitleSourceOrder detectSubtitleSourceOrder(Iterable<String> cues) {
  var legacy = 0, logical = 0;
  for (final line in cues.expand((cue) => cue.split('\n'))) {
    if (_legacyLine(line)) legacy++;
    if (_logicalLine(line)) logical++;
  }
  return legacy >= 2 && legacy > logical * 2
      ? SubtitleSourceOrder.legacyLtr
      : logical >= 2 && logical > legacy * 2
      ? SubtitleSourceOrder.logical
      : SubtitleSourceOrder.automatic;
}

String _logicalPunctuation(String line) {
  var prefix = '';
  final dialogue = _trailingDialogue.firstMatch(line);
  if (dialogue != null) {
    prefix = '${dialogue.group(1)} ';
    line = line.substring(0, dialogue.start);
  }
  final match = _leadingMark.firstMatch(line);
  if (match == null || !_legacyLine(line)) return '$prefix$line';
  return '$prefix${match.group(1)}${line.substring(match.end).trimRight()}${match.group(2)}';
}

String _markLatin(String line) => line
    .replaceAllMapped(_delimitedText, (match) {
      final text = match.group(0)!, inner = text.substring(1, text.length - 1);
      if (subtitleHasRtlLetters(inner) ||
          !_latinLetters.hasMatch(inner) ||
          !_terminalPunctuation.hasMatch(inner)) {
        return text;
      }
      return '${text.substring(0, text.length - 1)}\u200E${text[text.length - 1]}';
    })
    .replaceAllMapped(_latinPhrase, (match) {
      final text = match.group(0)!;
      return '\u200E$text${text.endsWith('++') || text.endsWith('#') ? '\u200E' : ''}';
    });

/// Canonical plain text. Explicit legacy mode is used once at the parser or
/// native track boundary; layout consumes that result without another repair.
String normalizePersianSubtitle(
  String input, {
  SubtitleSourceOrder sourceOrder = SubtitleSourceOrder.automatic,
}) => input
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .split('\n')
    .map((raw) {
      var line = raw.replaceAll(_directionControls, '');
      if (!subtitleHasRtlLetters(line) &&
          sourceOrder != SubtitleSourceOrder.legacyLtr) {
        return line;
      }
      if (sourceOrder == SubtitleSourceOrder.legacyLtr &&
          !_explicitDirection.hasMatch(raw)) {
        // English-only credits/dialogue keep their authored direction. An acronym
        // with a Persian stop/dialogue mark still belongs to the legacy RTL track.
        if (subtitleHasRtlLetters(line) ||
            RegExp(r'^[.،؛؟]|\s[-–—]$').hasMatch(line)) {
          line = legacySubtitleToLogical(line);
        }
      } else if (sourceOrder == SubtitleSourceOrder.automatic &&
          !_explicitDirection.hasMatch(raw) &&
          _legacyLine(line)) {
        final outsideDelimiters = line.replaceAll(_delimitedText, '');
        line = _latinLetters.hasMatch(outsideDelimiters)
            ? legacySubtitleToLogical(line)
            : _logicalPunctuation(line);
      }
      return subtitleHasRtlLetters(line) ? _markLatin(line) : line;
    })
    .join('\n');

/// Native mpv exposes cues, rather than an entire document. Accumulate bounded
/// evidence per media/track, including after seeks, and cache repeated events.
/// Empty cues do not reset the policy. Changing media/track always does.
class SubtitleTextNormalizer {
  Object? _track;
  final _samples = <String, String>{};
  var _order = SubtitleSourceOrder.automatic;
  SubtitleSourceOrder get sourceOrder => _order;

  List<String> normalize(List<String> cues, {required Object track}) {
    if (_track != track) {
      _track = track;
      _samples.clear();
      _order = SubtitleSourceOrder.automatic;
    }
    final result = <String>[];
    for (final cue in cues) {
      if (cue.trim().isEmpty) {
        result.add(cue);
        continue;
      }
      if (!_samples.containsKey(cue)) {
        _samples[cue] = '';
        if (_samples.length > 48) _samples.remove(_samples.keys.first);
        final detected = _order == SubtitleSourceOrder.automatic
            ? detectSubtitleSourceOrder(_samples.keys)
            : _order;
        if (detected == SubtitleSourceOrder.legacyLtr && detected != _order) {
          _order = detected;
          for (final key in _samples.keys.toList()) {
            _samples[key] = '';
          }
        }
      }
      result.add(
        _samples[cue]!.isNotEmpty
            ? _samples[cue]!
            : (_samples[cue] = normalizePersianSubtitle(
                cue,
                sourceOrder: _order,
              )),
      );
    }
    return result;
  }
}

/// Isolate each authored line, independently of the surrounding UI direction.
/// Parsed/native cues are already canonical; don't apply source repair twice.
String subtitleDisplayText(Iterable<String> cues, {bool normalized = false}) =>
    cues
        .expand(
          (cue) =>
              (normalized ? cue : normalizePersianSubtitle(cue)).split('\n'),
        )
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map(
          (line) =>
              subtitleHasRtlLetters(line) ||
                  RegExp(r'^[-–—].*[؟،؛]').hasMatch(line)
              ? '\u200F\u2067$line\u2069'
              : '\u200E\u2066$line\u2069',
        )
        .join('\n');
