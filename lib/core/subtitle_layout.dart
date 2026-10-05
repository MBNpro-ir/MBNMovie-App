import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Normalizes Arabic-script variants that Persian subtitle files often use.
///
/// SRT files frequently contain ARABIC LETTER YEH (U+064A, rendered WITH two
/// dots below) and ARABIC LETTER KAF (U+0643) instead of the Persian
/// FARSI YEH (U+06CC, no dots) and KEHEH (U+06A9). Each pair is the same
/// abstract letter with a different glyph, so the replacement is
/// semantically neutral and cannot alter any other word.
String normalizePersianSubtitle(String input) => _stabilizeBidi(
  input.replaceAll('ي', 'ی').replaceAll('ك', 'ک'),
);

/// Keep Latin/number runs together when a native subtitle is mostly RTL.
/// This prevents terms such as `MRI` from being reordered by Flutter's bidi
/// algorithm while leaving the authored ASS renderer untouched.
String _stabilizeBidi(String value) {
  if (!RegExp(r'[\u0600-\u06FF]').hasMatch(value)) return value;
  final isolate = RegExp(r'[A-Za-z0-9][A-Za-z0-9+./:_-]*');
  return value.replaceAllMapped(isolate, (match) {
    final start = match.start;
    final end = match.end;
    if ((start > 0 && value.codeUnitAt(start - 1) == 0x2066) ||
        (end < value.length && value.codeUnitAt(end) == 0x2069)) {
      return match.group(0)!;
    }
    return '\u2066${match.group(0)!}\u2069';
  });
}

/// Responsive measurements for the subtitle overlay in Android PiP.
///
/// The user's selected size remains the source of truth. In PiP it is scaled
/// against a 640x360 reference viewport and bounded so resizing the floating
/// window cannot make text microscopic or let a large preference cover video.
class SubtitleLayout {
  const SubtitleLayout({
    required this.fontSize,
    required this.horizontalInset,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.bottomPadding,
    required this.cornerRadius,
  });

  final double fontSize;
  final double horizontalInset;
  final double horizontalPadding;
  final double verticalPadding;
  final double bottomPadding;
  final double cornerRadius;

  factory SubtitleLayout.resolve({
    required Size viewport,
    required bool isPictureInPicture,
    required double preferredFontSize,
    required double preferredBottomPadding,
    required double preferredCornerRadius,
  }) {
    if (!isPictureInPicture) {
      return SubtitleLayout(
        fontSize: preferredFontSize,
        horizontalInset: 28,
        horizontalPadding: 16,
        verticalPadding: 7,
        bottomPadding: preferredBottomPadding,
        cornerRadius: preferredCornerRadius,
      );
    }

    final widthScale = viewport.width / 640;
    final heightScale = viewport.height / 360;
    final scale = math.min(widthScale, heightScale).clamp(.35, 1.0);
    return SubtitleLayout(
      fontSize: (preferredFontSize * scale).clamp(9.0, 22.0),
      horizontalInset: (28 * scale).clamp(6.0, 28.0),
      horizontalPadding: (16 * scale).clamp(5.0, 16.0),
      verticalPadding: (7 * scale).clamp(2.0, 7.0),
      bottomPadding: (preferredBottomPadding * scale).clamp(
        6.0,
        math.max(6.0, viewport.height * .24),
      ),
      cornerRadius: (preferredCornerRadius * scale).clamp(2.0, 14.0),
    );
  }
}
