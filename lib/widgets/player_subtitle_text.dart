import 'package:flutter/widgets.dart';
import '../core/subtitle_bidi.dart';

/// Shared text layer used by the player; never inherits UI layout direction.
class PlayerSubtitleText extends StatelessWidget {
  const PlayerSubtitleText({
    super.key,
    required this.lines,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  final List<String> lines;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final text = subtitleDisplayText(lines);
    return Text(
      text,
      textDirection: subtitleHasRtlLetters(text)
          ? TextDirection.rtl
          : TextDirection.ltr,
      textAlign: TextAlign.center,
      textScaler: TextScaler.noScaling,
      maxLines: maxLines,
      overflow: overflow,
      style: style,
    );
  }
}
