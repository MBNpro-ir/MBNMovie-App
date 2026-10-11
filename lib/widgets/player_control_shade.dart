import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shade only the control rows; the video between them stays unobscured.
class PlayerControlShade extends StatelessWidget {
  const PlayerControlShade({
    super.key,
    required this.child,
    this.minimum = EdgeInsets.zero,
  });
  final Widget child;
  final EdgeInsets minimum;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return CustomPaint(
      painter: _ControlShadePainter(
        math.max(padding.top, minimum.top),
        math.max(padding.bottom, minimum.bottom),
      ),
      child: child,
    );
  }
}

class _ControlShadePainter extends CustomPainter {
  const _ControlShadePainter(this.topInset, this.bottomInset);
  final double topInset, bottomInset;

  @override
  void paint(Canvas canvas, Size size) {
    final top = Rect.fromLTWH(
      0,
      0,
      size.width,
      math.min(88 + topInset, size.height * .24),
    );
    final bottomHeight = math.min(144 + bottomInset, size.height * .32);
    final bottom = Rect.fromLTWH(
      0,
      size.height - bottomHeight,
      size.width,
      bottomHeight,
    );
    canvas.drawRect(
      top,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ).createShader(top),
    );
    canvas.drawRect(
      bottom,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xD9000000), Colors.transparent],
        ).createShader(bottom),
    );
  }

  @override
  bool hitTest(Offset position) => false;

  @override
  bool shouldRepaint(_ControlShadePainter oldDelegate) =>
      topInset != oldDelegate.topInset ||
      bottomInset != oldDelegate.bottomInset;
}
