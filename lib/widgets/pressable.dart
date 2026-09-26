import 'package:flutter/material.dart';
import '../core/platform_ui.dart';
import '../core/theme.dart';

/// Subtle press-down feedback for tappable cards: scales to 96% while
/// pressed with a snappy spring back. Purely visual, keeps hit-testing
/// and semantics of [child] intact.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = .96,
  });

  final Widget child;
  final VoidCallback onTap;
  final double scale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  // Keyboard activation must work for TV remotes AND desktop keyboards:
  // limiting focus to TV left Windows keyboard-only users unable to Tab to
  // and activate poster cards. Mobile keeps touch behavior unchanged.
  Widget build(BuildContext context) => FocusableActionDetector(
    enabled: isAndroidTv || isDesktopWindow,
    onFocusChange: (focused) {
      setState(() => _focused = focused);
      if (focused) {
        Scrollable.ensureVisible(
          context,
          alignment: .5,
          duration: const Duration(milliseconds: 160),
        );
      }
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) {
          widget.onTap();
          return null;
        },
      ),
    },
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _focused ? MovieColors.cyan : Colors.transparent,
          width: 3,
        ),
      ),
      child: Semantics(
        button: true,
        enabled: true,
        // Focus ring state is exposed to assistive tech on TV/desktop.
        focused: _focused,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed ? widget.scale : 1,
            duration: Duration(milliseconds: _pressed ? 65 : 150),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    ),
  );
}
