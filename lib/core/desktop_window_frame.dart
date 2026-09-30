import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'theme.dart';
import 'platform_ui.dart';

class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return child;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: MovieColors.background,
        // The player hides the title bar for true fullscreen video.
        child: ValueListenableBuilder<bool>(
          valueListenable: hideWindowChrome,
          builder: (_, hidden, content) => Column(
            children: [
              if (!hidden) const _DesktopTitleBar(),
              Expanded(child: content!),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DesktopTitleBar extends StatefulWidget {
  const _DesktopTitleBar();

  @override
  State<_DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<_DesktopTitleBar>
    with WindowListener {
  bool _maximized = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final value = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = value);
    } catch (_) {
      // Ignore: window not ready yet (e.g. in tests).
    }
  }

  @override
  void onWindowMaximize() => _syncMaximized();

  @override
  void onWindowUnmaximize() => _syncMaximized();

  @override
  void onWindowRestore() => _syncMaximized();

  @override
  void onWindowDocked() => _syncMaximized();

  @override
  void onWindowUndocked() => _syncMaximized();

  @override
  void onWindowFocus() {
    if (mounted) setState(() => _active = true);
  }

  @override
  void onWindowBlur() {
    if (mounted) setState(() => _active = false);
  }

  void _minimize() => windowManager.minimize();

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {
      // Ignore window errors.
    }
    await _syncMaximized();
  }

  void _close() => windowManager.close();

  @override
  Widget build(BuildContext context) {
    // Native Windows caption is 32px. We use 36px so the Persian font
    // stays readable without looking oversized.
    const barHeight = 36.0;
    return SizedBox(
      height: barHeight,
      child: Material(
        color: MovieColors.surface,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFF242936))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag area fills all free space. DragToMoveArea already
              // handles drag + double-click to maximize, so it must NOT
              // be wrapped in another GestureDetector.
              Expanded(
                child: DragToMoveArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        const _MiniBrand(),
                        const SizedBox(width: 8),
                        Opacity(
                          opacity: _active ? 1 : 0.55,
                          child: Text.rich(
                            const TextSpan(
                              children: [
                                TextSpan(
                                  text: 'MBN',
                                  style: TextStyle(
                                    fontFamily: 'Vazirmatn',
                                    fontSize: 13,
                                    height: 1.2,
                                    letterSpacing: 0.3,
                                    fontWeight: FontWeight.w600,
                                    color: MovieColors.text,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Movie',
                                  style: TextStyle(
                                    fontFamily: 'Vazirmatn',
                                    fontSize: 8,
                                    height: 1.2,
                                    letterSpacing: 0.3,
                                    fontWeight: FontWeight.w700,
                                    color: MovieColors.orange,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // NOTE: no Tooltip here on purpose. This bar lives in
              // MaterialApp.builder, above the Navigator/Overlay, and
              // Tooltip requires an Overlay ancestor (it crashed the app).
              WindowCaptionButton.minimize(
                brightness: Brightness.dark,
                onPressed: _minimize,
              ),
              _maximized
                  ? WindowCaptionButton.unmaximize(
                      brightness: Brightness.dark,
                      onPressed: _toggleMaximize,
                    )
                  : WindowCaptionButton.maximize(
                      brightness: Brightness.dark,
                      onPressed: _toggleMaximize,
                    ),
              WindowCaptionButton.close(
                brightness: Brightness.dark,
                onPressed: _close,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBrand extends StatelessWidget {
  const _MiniBrand();
  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [MovieColors.orange, MovieColors.coral],
      ),
      borderRadius: BorderRadius.circular(6),
    ),
    child: const Icon(Icons.play_arrow_rounded, size: 14, color: Colors.white),
  );
}
