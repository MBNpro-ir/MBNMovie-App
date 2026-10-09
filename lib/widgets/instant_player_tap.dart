import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import '../services/device_performance.dart';

class InstantPlayerTap extends StatefulWidget {
  const InstantPlayerTap({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = EdgeInsets.zero,
    this.decoration,
    this.activateOnPress,
    this.tooltip,
  });

  final Widget child;
  final bool? activateOnPress;
  final VoidCallback onTap;
  final EdgeInsetsGeometry padding;
  final Decoration? decoration;
  final String? tooltip;

  @override
  State<InstantPlayerTap> createState() => InstantPlayerTapState();
}

class InstantPlayerTapState extends State<InstantPlayerTap> {
  bool _pressed = false;
  bool _focused = false;
  int? _pointer;
  Offset? _origin;

  void _press(PointerDownEvent event) {
    if (_pressed || event.buttons != kPrimaryButton) return;
    _pointer = event.pointer;
    _origin = event.position;
    setState(() => _pressed = true);
    if (widget.activateOnPress ?? !kIsWeb) widget.onTap();
  }

  void _release(PointerEvent event) {
    if (event.pointer != _pointer) return;
    final box = context.findRenderObject() as RenderBox?;
    final activate =
        event is PointerUpEvent &&
        _origin != null &&
        (event.position - _origin!).distance <= kTouchSlop &&
        box != null &&
        (Offset.zero & box.size).contains(box.globalToLocal(event.position));
    _pointer = null;
    _origin = null;
    if (_pressed && mounted) setState(() => _pressed = false);
    if (activate && !(widget.activateOnPress ?? !kIsWeb)) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    Widget result = Semantics(
      button: true,
      label: widget.tooltip,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _press,
          onPointerUp: _release,
          onPointerCancel: _release,
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            gestures: {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
            },

            child: AnimatedScale(
              scale: _pressed ? .88 : 1,
              duration: Duration(
                milliseconds: DevicePerformance.appleMobileWeb
                    ? 0
                    : (_pressed ? 55 : 210),
              ),
              curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
              child: AnimatedOpacity(
                opacity: _pressed ? .72 : 1,
                duration: Duration(
                  milliseconds: DevicePerformance.appleMobileWeb ? 0 : 70,
                ),
                // NOTE: no `alignment` on this Container on purpose. A
                // non-null alignment makes it expand to fill loose
                // constraints, which turned the unlock control into a
                // full-screen button. Inner Center keeps content centered.
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 46,
                    minHeight: 46,
                  ),
                  padding: widget.padding,
                  decoration: widget.decoration,
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) {
      result = Tooltip(message: widget.tooltip!, child: result);
    }
    return FocusableActionDetector(
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
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
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: result,
      ),
    );
  }
}
