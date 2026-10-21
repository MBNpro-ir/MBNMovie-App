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
final _delimitedText = RegExp(
  r'''"[^"\n]*"|'[^'\n]*'|«[^«»\n]*»|“[^“”\n]*”|‘[^‘’\n]*’|\([^()\n]*\)|\[[^\[\]\n]*\]|\{[^{}\n]*\}''',
);
final _terminalPunctuation = RegExp(r'[.!?,;:…]+[ \t]*$');

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
          ? _markLatinPunctuation(line).replaceAllMapped(_latinPhrase, (match) {
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
