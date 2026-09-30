import 'package:flutter/material.dart';

import '../core/theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.size = 54,
    this.showWordmark = true,
    this.gradientColors = const [MovieColors.orange, MovieColors.coral],
    this.accent = MovieColors.orange,
  });

  final double size;
  final bool showWordmark;
  final List<Color> gradientColors;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    // Logo order is always LTR (icon then wordmark) even inside RTL screens,
    // so the in-app centered title matches the Windows caption.
    return Row(
      mainAxisSize: MainAxisSize.min,
      textDirection: TextDirection.ltr,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(size * .5),
              topRight: Radius.circular(size * .24),
              bottomLeft: Radius.circular(size * .24),
              bottomRight: Radius.circular(size * .5),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: .28),
                blurRadius: (size * 0.45).clamp(8.0, 24.0),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            size: size * .62,
            color: Colors.white,
          ),
        ),
        if (showWordmark) ...[
          SizedBox(width: (size * 0.22).clamp(5.0, 12.0)),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'MBN',
                  style: (Theme.of(context).textTheme.titleLarge ?? const TextStyle()).copyWith(
                    fontSize: (size * 0.52).clamp(13.0, 22.0),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(
                  text: 'Movie',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    // Suffix is intentionally much smaller than MBN.
                    fontSize: (size * 0.30).clamp(8.0, 13.0),
                  ),
                ),
              ],
            ),
            textDirection: TextDirection.ltr,
          ),
        ],
      ],
    );
  }
}
