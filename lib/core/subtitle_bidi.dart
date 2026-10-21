// Plain subtitle rendering only. Original ASS keeps its authored layout.
final _rtlLetters = RegExp(
  r'[\u0590-\u05FF\u0620-\u064A\u066E-\u066F\u0671-\u06D3\u06D5\u06EE-\u06EF\u06FA-\u06FC\u0750-\u077F\u08A0-\u08C9\uFB1D-\uFDFF\uFE70-\uFEFC]',
);
final _directionControls = RegExp(
  r'[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
);
final _latinPhrase = RegExp(
  r"(?:[+-](?=[0-9]))?[A-Za-z0-9]+(?:[+./:_'\-][A-Za-z0-9]+)*(?:[ \t]+[A-Za-z0-9]+(?:[+./:_'\-][A-Za-z0-9]+)*)*(?:\+\+|#)?",
);
final _latinLetters = RegExp(r'[A-Za-z]');
final _rtlWord = RegExp(
  r'[\u0590-\u05FF\u0620-\u064A\u066E-\u066F\u0671-\u06D3\u06D5\u06EE-\u06EF\u06FA-\u06FC\u0750-\u077F\u08A0-\u08C9\uFB1D-\uFDFF\uFE70-\uFEFC]+',
);
final _visualOrderSuffix = <String>{
  'و',
  'اما',
  'ولی',
  'که',
  'از',
  'به',
  'در',
  'با',
  'برای',
  'این',
  'آن',
  'یک',
};
final _visualOrderPrefix = <String>{'از', 'به', 'در', 'با', 'برای'};
final _visualOrderVerbTail = <String>{
  'است',
  'هست',
  'بود',
  'شد',
  'شدن',
  'دارد',
  'ندارد',
};
final _delimitedText = RegExp(
  r'''"[^"\n]*"|'[^'\n]*'|«[^«»\n]*»|“[^“”\n]*”|‘[^‘’\n]*’|\([^()\n]*\)|\[[^\[\]\n]*\]|\{[^{}\n]*\}''',
);
final _terminalPunctuation = RegExp(r'[.!?,;:…]+[ \t]*$');

final _legacyLeadingPunctuation = RegExp(
  r'^([ \t]*(?:[-–—][ \t]*)?)([.,،;؛!?؟]+)[ \t]*',
);
final _openingDelimiters = RegExp(r'''^[ \t"'«“‘(\[{]*''');

String _logicalRtlPunctuation(String line) {
  final match = _legacyLeadingPunctuation.firstMatch(line);
  if (match == null) return line;
  final punctuation = match.group(2)!;
  // Some older Persian subtitles store terminal marks at the logical start
  // to compensate for LTR-only players. The RTL renderer must first restore
  // logical order. Leave intentional leading ellipses, .NET, decimals and
  // decorative punctuation alone; a Persian sentence must follow the mark.
  if (punctuation.contains('..')) return line;
  var sentence = line.substring(match.end).trimRight();
  final content = sentence.replaceFirst(_openingDelimiters, '');
  if (_rtlLetters.matchAsPrefix(content) == null) return line;
  var prefix = match.group(1)!;
  // Legacy dialogue may also put its dash at the opposite edge: !سلام -
  // Preserve the speaker marker when restoring that same authored convention.
  final dialogue = RegExp(r'[ \t]+([-–—])$').firstMatch(sentence);
  if (prefix.trim().isEmpty && dialogue != null) {
    prefix = '$prefix${dialogue.group(1)} ';
    sentence = sentence.substring(0, dialogue.start);
  }
  return '$prefix$sentence$punctuation';
}

bool _insideDelimitedText(String line, int start, int end) => _delimitedText
    .allMatches(line)
    .any((match) => match.start <= start && match.end >= end);

/// A few older Persian subtitle sources were authored in visual order around
/// Latin acronyms. For example, `هم روی صورتت هست KS و نهایتا یه زخم` is the
/// visual-order form of `و نهایتا یه زخم KS هم روی صورتت هست`. Rotate only when
/// the Latin run is between two substantial RTL chunks and the boundary words
/// look like a sentence continuation. This leaves normal logical lines such as
/// `نتیجه (MRI, CT) آماده است` and `این فیلم House را دیدم` untouched.
String _repairVisualMixedOrder(String line) {
  final matches = _latinPhrase.allMatches(line).where((match) {
    final text = match.group(0)!;
    return _latinLetters.hasMatch(text) &&
        subtitleHasRtlLetters(line.substring(0, match.start)) &&
        subtitleHasRtlLetters(line.substring(match.end)) &&
        !_insideDelimitedText(line, match.start, match.end);
  }).toList();
  for (final match in matches) {
    final before = line.substring(0, match.start).trimRight();
    final after = line.substring(match.end).trimLeft();
    final beforeWords = _rtlWord
        .allMatches(before)
        .map((m) => m.group(0)!)
        .toList(growable: false);
    final afterWords = _rtlWord
        .allMatches(after)
        .map((m) => m.group(0)!)
        .toList(growable: false);
    if (beforeWords.length < 2 || afterWords.isEmpty) continue;
    final afterLead = afterWords.first;
    final beforeLead = beforeWords.first;
    final beforeTail = beforeWords.last;
    final verbLikeTail =
        _visualOrderVerbTail.contains(beforeTail) ||
        beforeTail.startsWith('می') ||
        beforeTail.startsWith('نمی');
    if (!_visualOrderSuffix.contains(afterLead) &&
        !(beforeWords.length >= 3 &&
            afterWords.length <= 2 &&
            _visualOrderPrefix.contains(beforeLead) &&
            verbLikeTail)) {
      continue;
    }
    if (_visualOrderSuffix.contains(afterLead) &&
        (beforeWords.length < 3 || !verbLikeTail)) {
      continue;
    }
    // Keep a terminal mark attached to the sentence after rotating the chunks.
    final terminal = RegExp(r'([.!?,;:…،؛؟]+)[ \t]*$').firstMatch(after);
    final afterBody = terminal == null
        ? after
        : after.substring(0, terminal.start).trimRight();
    final punctuation = terminal?.group(1) ?? '';
    final prefix = before.trim();
    final latin = match.group(0)!.trim();
    return '${afterBody.isEmpty ? '' : '$afterBody '}$latin $prefix$punctuation';
  }
  return line;
}

String _markLatinPunctuation(
  String line,
) => line.replaceAllMapped(_delimitedText, (match) {
  final text = match.group(0)!;
  final inner = text.substring(1, text.length - 1);
  if (subtitleHasRtlLetters(inner) ||
      !_latinLetters.hasMatch(inner) ||
      !_terminalPunctuation.hasMatch(inner)) {
    return text;
  }
  // A fully Latin quote/parenthetical owns its terminal punctuation. The
  // closing LRM keeps `!` in «Hello!» and the final dot in (M.D.) on its
  // Latin side without turning the phrase into a separate neutral object.
  return '${text.substring(0, text.length - 1)}\u200E${text[text.length - 1]}';
});

bool subtitleHasRtlLetters(String text) => _rtlLetters.hasMatch(text);

/// Normalize once at the common web/native text boundary. Reapplying this is
/// idempotent: stale embedding overrides and existing isolates are removed,
/// while Persian joiners (including ZWNJ) and authored text remain intact.
/// Do not isolate individual Latin words: that splits expressions such as
/// `(MRI, CT)` into separate neutral objects inside the RTL paragraph and
/// reverses them. An LRM is a strong L character, not an isolated object: it
/// keeps weak leading digits in `720p` / `12.50 USD` with their Latin text while
/// letting Unicode bidi resolve commas and paired brackets across Latin runs.
/// Only the authored line's base direction is isolated below.
String normalizePersianSubtitle(String input) => input
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(_directionControls, '')
    .split('\n')
    .map(
      (line) => subtitleHasRtlLetters(line)
          ? _markLatinPunctuation(
              _repairVisualMixedOrder(_logicalRtlPunctuation(line)),
            ).replaceAllMapped(_latinPhrase, (match) {
              final text = match.group(0)!;
              final suffix = text.endsWith('++') || text.endsWith('#')
                  ? '\u200E'
                  : '';
              return '\u200E$text$suffix';
            })
          : line,
    )
    .join('\n');

/// Each authored line owns its base direction, independent of the surrounding
/// player/widget/browser direction. Marks also set WebVTT's first-strong base;
/// isolates keep dialogue dashes, brackets and English-only lines in place.
String subtitleDisplayText(Iterable<String> cues) => cues
    .expand((cue) => normalizePersianSubtitle(cue).split('\n'))
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .map(
      (line) => subtitleHasRtlLetters(line)
          ? '\u200F\u2067$line\u2069'
          : '\u200E\u2066$line\u2069',
    )
    .join('\n');
