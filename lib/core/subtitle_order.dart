import 'package:characters/characters.dart';
import 'subtitle_unicode.dart';

typedef _B = SubtitleBidiClass;

/// The text in old LTR-player subtitles is logical *within* directional runs,
/// but the runs have LTR paragraph order. Convert that convention to logical
/// RTL before layout/wrapping. Never reverse Arabic letters or English words.
///
/// This uses UAX #9 weak/neutral/implicit resolution and L2 twice: logical LTR
/// to visual, then visual to logical RTL (numbers are L in the inverse pass).
/// No shaping, font measurement, UI work, or media-player reconfiguration.
String legacySubtitleToLogical(String line) =>
    _reorder(_reorder(line, inverse: false), inverse: true);

String _reorder(String line, {required bool inverse}) {
  final chars = line.characters.toList(growable: false);
  if (chars.isEmpty) return line;
  final types = chars.map((c) => subtitleBidiClass(c.runes.first)).toList();
  final original = List<_B>.of(types);
  final base = inverse ? _B.R : _B.L;
  var previous = base;
  // W1-W3. Combining sequences stay attached to their base grapheme.
  for (var i = 0; i < types.length; i++) {
    if (types[i] == _B.NSM) types[i] = previous;
    previous = types[i];
  }
  previous = base;
  for (var i = 0; i < types.length; i++) {
    final type = types[i];
    if (type == _B.EN && previous == _B.AL) types[i] = _B.AN;
    if (type == _B.L || type == _B.R || type == _B.AL) previous = type;
    if (type == _B.AL) types[i] = _B.R;
  }
  // W4-W6: numbers, decimal separators, signs, currency and neutral marks.
  for (var i = 1; i + 1 < types.length; i++) {
    final before = types[i - 1], after = types[i + 1];
    if ((types[i] == _B.ES && before == _B.EN && after == _B.EN) ||
        (types[i] == _B.CS &&
            before == after &&
            (before == _B.EN || before == _B.AN))) {
      types[i] = before;
    }
  }
  for (var i = 0; i < types.length; i++) {
    if (types[i] != _B.ET) continue;
    final start = i;
    while (i + 1 < types.length && types[i + 1] == _B.ET) {
      i++;
    }
    if ((start > 0 && types[start - 1] == _B.EN) ||
        (i + 1 < types.length && types[i + 1] == _B.EN)) {
      for (var j = start; j <= i; j++) {
        types[j] = _B.EN;
      }
    }
  }
  previous = base;
  for (var i = 0; i < types.length; i++) {
    if ({_B.ES, _B.ET, _B.CS, _B.BN}.contains(types[i])) types[i] = _B.ON;
    if (types[i] == _B.EN && previous == _B.L) types[i] = _B.L;
    if (types[i] == _B.L || types[i] == _B.R) previous = types[i];
    if (inverse && (types[i] == _B.EN || types[i] == _B.AN)) types[i] = _B.L;
  }
  _resolveBrackets(chars, types, original, base);
  _B strong(_B type) => type == _B.L ? _B.L : _B.R;
  bool isStrong(_B type) =>
      type == _B.L || type == _B.R || type == _B.EN || type == _B.AN;
  // N1/N2. The source has no embeddings/overrides here; they were removed at
  // the plain-text boundary. Authored ASS never passes through this function.
  for (var i = 0; i < types.length; i++) {
    if (isStrong(types[i])) continue;
    final start = i;
    while (i + 1 < types.length && !isStrong(types[i + 1])) {
      i++;
    }
    final before = start == 0 ? base : strong(types[start - 1]);
    final after = i + 1 == types.length ? base : strong(types[i + 1]);
    for (var j = start; j <= i; j++) {
      types[j] = before == after ? before : base;
    }
  }
  // I1/I2 and L2. Mirror only the codepoints whose resolved level is odd;
  // grapheme boundaries protect accents, joiners, surrogate pairs and emoji.
  final levels = types
      .map(
        (t) => inverse
            ? (t == _B.L ? 2 : 1)
            : (t == _B.R ? 1 : (t == _B.EN || t == _B.AN ? 2 : 0)),
      )
      .toList();
  final indices = List.generate(chars.length, (i) => i);
  for (var level = 2; level >= 1; level--) {
    for (var i = 0; i < indices.length; i++) {
      if (levels[indices[i]] < level) continue;
      final start = i;
      while (i + 1 < indices.length && levels[indices[i + 1]] >= level) {
        i++;
      }
      var left = start, right = i;
      while (left < right) {
        final saved = indices[left];
        indices[left++] = indices[right];
        indices[right--] = saved;
      }
    }
  }
  return indices
      .map(
        (i) => levels[i].isEven
            ? chars[i]
            : String.fromCharCodes(
                chars[i].runes.map((r) => subtitleBidiMirrors[r] ?? r),
              ),
      )
      .join();
}

void _resolveBrackets(
  List<String> chars,
  List<_B> types,
  List<_B> original,
  _B base,
) {
  final stack = <(int, int)>[], pairs = <(int, int)>[];
  int canonical(int r) => r == 0x232A ? 0x3009 : r;
  for (var i = 0; i < chars.length; i++) {
    if (types[i] != _B.ON) continue;
    final rune = chars[i].runes.first, bracket = subtitleBidiBrackets[rune];
    if (bracket == null) continue;
    if (bracket.$2) {
      if (stack.length >= 63) break;
      stack.add((i, canonical(bracket.$1)));
    } else {
      for (var j = stack.length - 1; j >= 0; j--) {
        if (stack[j].$2 != canonical(rune)) continue;
        pairs.add((stack[j].$1, i));
        stack.removeRange(j, stack.length);
        break;
      }
    }
  }
  pairs.sort((a, b) => a.$1.compareTo(b.$1));
  _B? strong(_B t) =>
      t == _B.L ? _B.L : (t == _B.R || t == _B.EN || t == _B.AN ? _B.R : null);
  for (final (open, close) in pairs) {
    _B? inside;
    for (var i = open + 1; i < close; i++) {
      final type = strong(types[i]);
      if (type == base) {
        inside = base;
        break;
      }
      inside ??= type;
    }
    if (inside == null) continue;
    var resolved = base;
    if (inside != base) {
      var before = base;
      for (var i = open - 1; i >= 0; i--) {
        final type = strong(types[i]);
        if (type != null) {
          before = type;
          break;
        }
      }
      if (before == inside) resolved = inside;
    }
    for (final position in [open, close]) {
      types[position] = resolved;
      for (
        var i = position + 1;
        i < types.length && original[i] == _B.NSM;
        i++
      ) {
        types[i] = resolved;
      }
    }
  }
}
