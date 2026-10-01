import '../services/device_performance.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    required this.child,
    this.animate = false,
  });

  final Widget child;
  final bool animate;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.animate && !DevicePerformance.lightweight) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (DevicePerformance.lightweight) {
      return ColoredBox(color: MovieColors.background, child: widget.child);
    }
    return ColoredBox(
      color: MovieColors.background,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _AmbientPainter(_controller.value),
            child: child,
          ),
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  const _AmbientPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final orange = Paint()
      ..shader =
          RadialGradient(
            colors: [
              MovieColors.orange.withValues(alpha: .18),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(
                size.width * (.82 - .07 * math.sin(t * math.pi)),
                size.height * .10,
              ),
              radius: size.width * .78,
            ),
          );
    final violet = Paint()
      ..shader =
          RadialGradient(
            colors: [
              MovieColors.violet.withValues(alpha: .12),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(
                size.width * .05,
                size.height * (.72 + .05 * math.cos(t * math.pi)),
              ),
              radius: size.width * .72,
            ),
          );
    canvas.drawRect(Offset.zero & size, orange);
    canvas.drawRect(Offset.zero & size, violet);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) =>
      oldDelegate.t != t;
}
