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
    return Row(
      mainAxisSize: MainAxisSize.min,
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
                blurRadius: 24,
                spreadRadius: 2,
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
          const SizedBox(width: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'MBN',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextSpan(
                  text: 'Movie',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w700,
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
