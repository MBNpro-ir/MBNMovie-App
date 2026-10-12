// Plain subtitle rendering only. Original ASS keeps its authored layout.
final _rtlLetters = RegExp(
  r'[\u0590-\u05FF\u0620-\u064A\u066E-\u066F\u0671-\u06D3\u06FA-\u06FC\u0750-\u077F\u08A0-\u08C9]',
);
final _directionControls = RegExp(
  r'[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]',
);
final _latinPhrase = RegExp(
  r"[A-Za-z0-9]+(?:[+./:_'\-][A-Za-z0-9]+)*(?:[ \t]+[A-Za-z0-9]+(?:[+./:_'\-][A-Za-z0-9]+)*)*",
);

bool subtitleHasRtlLetters(String text) => _rtlLetters.hasMatch(text);

/// Normalize once at the common web/native text boundary. Reapplying this is
/// idempotent: stale embedding overrides and existing isolates are replaced,
/// while Persian joiners (including ZWNJ) and authored text remain intact.
String normalizePersianSubtitle(String input) => input
    .replaceAll('ي', 'ی')
    .replaceAll('ك', 'ک')
    .replaceAll(_directionControls, '')
    .split('\n')
    .map(
      (line) => subtitleHasRtlLetters(line)
          ? line.replaceAllMapped(
              _latinPhrase,
              (match) => '\u2066${match.group(0)}\u2069',
            )
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
