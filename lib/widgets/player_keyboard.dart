import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Duration playerSeekTarget(Duration position, Duration duration, int seconds) {
  final target = position.inMilliseconds + seconds * 1000;
  return Duration(
    milliseconds: target.clamp(
      0,
      duration.inMilliseconds > 0 ? duration.inMilliseconds : target.abs(),
    ),
  );
}

enum PlayerCommand {
  toggle,
  back,
  forward,
  volumeUp,
  volumeDown,
  mute,
  fullscreen,
  exitFullscreen,
  faster,
  slower,
  subtitles,
  tracks,
  subtitleSettings,
  fit,
  home,
  end,
  help,
}

class PlayerKeyboard extends StatelessWidget {
  const PlayerKeyboard({
    super.key,
    required this.child,
    required this.onCommand,
    required this.onSeekFraction,
    required this.onFocus,
    this.isTelevision = false,
    this.controlsVisible = true,
    this.onRemoteNavigation,
  });
  final Widget child;
  final void Function(PlayerCommand) onCommand;
  final void Function(double) onSeekFraction;
  final VoidCallback onFocus;
  final bool isTelevision;
  final bool controlsVisible;
  final VoidCallback? onRemoteNavigation;
  static const help =
      'Space / K: پخش و توقف\n← / →: ده ثانیه عقب و جلو\n↑ / ↓: صدا\nM: قطع صدا\nF / F11: تمام‌صفحه\nEsc: خروج از تمام‌صفحه\n[ / ]: سرعت پخش\n0 تا 9: رفتن به درصد ویدئو\nHome / End: ابتدا و انتها\nC: زیرنویس روشن/خاموش\nA: ترک صدا و زیرنویس\nS: تنظیمات زیرنویس\nV: اندازهٔ تصویر\nTab و Shift+Tab: جابه‌جایی بین کنترل‌ها\nEnter: فعال‌کردن دکمهٔ انتخاب‌شده\nF1: راهنمای کلیدها';

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      for (final pair in const [
        (LogicalKeyboardKey.space, PlayerCommand.toggle),
        (LogicalKeyboardKey.keyK, PlayerCommand.toggle),
        (LogicalKeyboardKey.mediaPlayPause, PlayerCommand.toggle),
        (LogicalKeyboardKey.keyM, PlayerCommand.mute),
        (LogicalKeyboardKey.keyF, PlayerCommand.fullscreen),
        (LogicalKeyboardKey.f11, PlayerCommand.fullscreen),
        (LogicalKeyboardKey.escape, PlayerCommand.exitFullscreen),
        (LogicalKeyboardKey.bracketRight, PlayerCommand.faster),
        (LogicalKeyboardKey.bracketLeft, PlayerCommand.slower),
        (LogicalKeyboardKey.keyC, PlayerCommand.subtitles),
        (LogicalKeyboardKey.keyA, PlayerCommand.tracks),
        (LogicalKeyboardKey.keyS, PlayerCommand.subtitleSettings),
        (LogicalKeyboardKey.keyV, PlayerCommand.fit),
        (LogicalKeyboardKey.home, PlayerCommand.home),
        (LogicalKeyboardKey.end, PlayerCommand.end),
        (LogicalKeyboardKey.f1, PlayerCommand.help),
      ])
        SingleActivator(pair.$1): () => onCommand(pair.$2),
      if (!isTelevision) ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            onCommand(PlayerCommand.back),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            onCommand(PlayerCommand.forward),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            onCommand(PlayerCommand.volumeUp),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            onCommand(PlayerCommand.volumeDown),
      },
      for (var i = 0; i < 10; i++)
        SingleActivator(
          LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i),
        ): () =>
            onSeekFraction(i / 10),
    },
    child: _PlayerKeyScope(
      onCommand: onCommand,
      onFocus: onFocus,
      isTelevision: isTelevision,
      controlsVisible: controlsVisible,
      onRemoteNavigation: onRemoteNavigation,
      child: child,
    ),
  );
}

/// Slider shortcuts reverse direction in RTL. Capture physical seek keys only
/// inside this player focus subtree, before a focused slider can consume them.
class _PlayerKeyScope extends StatefulWidget {
  const _PlayerKeyScope({
    required this.child,
    required this.onCommand,
    required this.onFocus,
    required this.isTelevision,
    required this.controlsVisible,
    this.onRemoteNavigation,
  });
  final Widget child;
  final ValueChanged<PlayerCommand> onCommand;
  final VoidCallback onFocus;
  final bool isTelevision;
  final bool controlsVisible;
  final VoidCallback? onRemoteNavigation;
  @override
  State<_PlayerKeyScope> createState() => _PlayerKeyScopeState();
}

class _PlayerKeyScopeState extends State<_PlayerKeyScope> {
  final _focus = FocusNode(debugLabel: 'Player physical keys');
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_key);
  }

  KeyEventResult _key(KeyEvent event) {
    if (!_focus.hasFocus ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (widget.isTelevision) {
      final key = event.logicalKey;
      final select =
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.gameButtonA;
      if (select && (!widget.controlsVisible || _focus.hasPrimaryFocus)) {
        if (event is KeyDownEvent) widget.onCommand(PlayerCommand.toggle);
        return KeyEventResult.handled;
      }
      if (!widget.controlsVisible) {
        if (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight) {
          widget.onCommand(
            key == LogicalKeyboardKey.arrowLeft
                ? PlayerCommand.back
                : PlayerCommand.forward,
          );
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp) {
          widget.onRemoteNavigation?.call();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focus.nextFocus();
          });
          return KeyEventResult.handled;
        }
      } else {
        widget.onRemoteNavigation?.call();
        return KeyEventResult.ignored;
      }
    }
    final command = switch (event.physicalKey) {
      PhysicalKeyboardKey.arrowRight => PlayerCommand.forward,
      PhysicalKeyboardKey.arrowLeft => PlayerCommand.back,
      PhysicalKeyboardKey.arrowUp => PlayerCommand.volumeUp,
      PhysicalKeyboardKey.arrowDown => PlayerCommand.volumeDown,
      _ => null,
    };
    if (command == null) return KeyEventResult.ignored;
    widget.onCommand(command);
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_key);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _focus,
    autofocus: true,
    onFocusChange: (focused) {
      if (focused) widget.onFocus();
    },
    child: widget.child,
  );
}
