import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool isWideWebLayout(BuildContext context) =>
    kIsWeb && MediaQuery.sizeOf(context).width >= 900;

double webPanelHeight(BuildContext context, {required double desired}) {
  final media = MediaQuery.of(context);
  return math.min(
    desired,
    math.max(
      0,
      media.size.height -
          media.padding.vertical -
          media.viewInsets.bottom -
          100,
    ),
  );
}

class ResponsiveContentFrame extends StatelessWidget {
  const ResponsiveContentFrame({
    super.key,
    required this.child,
    this.enabled = true,
  });
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) => enabled
      ? Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: child,
          ),
        )
      : child;
}

/// Desktop web panels stay near the action instead of filling a monitor.
/// On phones the existing bottom sheet keeps its gestures and safe areas.
Future<T?> showResponsivePlayerPanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  BoxConstraints? constraints,
  bool isScrollControlled = true,
  bool useSafeArea = true,
  bool showDragHandle = true,
  Color? backgroundColor,
}) {
  final media = MediaQuery.of(context);
  if (kIsWeb && media.size.width >= 700 && media.size.height >= 480) {
    return showDialog<T>(
      context: context,
      builder: (context) => PlayerWebPanel(
        maxWidth: constraints?.maxWidth ?? 640,
        color: backgroundColor,
        child: Builder(builder: builder),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    showDragHandle: showDragHandle,
    backgroundColor: backgroundColor,
    constraints: kIsWeb
        ? BoxConstraints(
            maxWidth: math.min(
              constraints?.maxWidth ?? 640,
              media.size.width - 16,
            ),
            maxHeight: math.max(
              0,
              media.size.height -
                  media.padding.top -
                  media.viewInsets.bottom -
                  8,
            ),
          )
        : constraints,
  );
}

class PlayerWebPanel extends StatelessWidget {
  const PlayerWebPanel({
    super.key,
    required this.child,
    this.maxWidth = 640,
    this.color,
  });
  final Widget child;
  final double maxWidth;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = math.min(
      720.0,
      math.max(
        0.0,
        media.size.height -
            media.padding.vertical -
            media.viewInsets.bottom -
            40,
      ),
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: color,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height),
        child: SizedBox(
          key: const Key('player-web-panel'),
          width: math.min(maxWidth, media.size.width - 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: 'بستن پنل',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// Preparation takes the place of play, so its label cannot sit behind it.
class PreparationControls extends StatelessWidget {
  const PreparationControls({
    super.key,
    required this.preparing,
    required this.child,
  });
  final ValueListenable<bool> preparing;
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: preparing,
    child: child,
    builder: (_, value, child) => value ? const SizedBox.shrink() : child!,
  );
}

class PlaybackPreparationNotice extends StatelessWidget {
  const PlaybackPreparationNotice({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'در حال آماده‌سازی پخش…',
    liveRegion: true,
    child: IgnorePointer(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: const Color(0xD910131B),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 14),
              ExcludeSemantics(
                child: Text(
                  'در حال آماده‌سازی پخش…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PlayerLoadingIndicator extends StatelessWidget {
  const PlayerLoadingIndicator({
    super.key,
    required this.preparing,
    required this.buffering,
    required this.enabled,
  });
  final ValueListenable<bool> preparing;
  final bool buffering, enabled;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: preparing,
    builder: (_, value, _) {
      if (!enabled) return const SizedBox.shrink();
      if (value) return const PlaybackPreparationNotice();
      return buffering
          ? const IgnorePointer(
              child: Center(child: CircularProgressIndicator()),
            )
          : const SizedBox.shrink();
    },
  );
}

class SubtitlePanelToolbar extends StatelessWidget {
  const SubtitlePanelToolbar({
    super.key,
    required this.onReset,
    required this.onSave,
  });
  final VoidCallback onReset, onSave;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final heading = Row(
        children: [
          IconButton(
            tooltip: 'بستن',
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'تنظیمات ظاهر زیرنویس',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      );
      final actions = Wrap(
        spacing: 8,
        alignment: WrapAlignment.end,
        children: [
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('پیش‌فرض'),
          ),
          FilledButton.icon(
            onPressed: onSave,
            icon: const Icon(Icons.check_rounded),
            label: const Text('ذخیره'),
          ),
        ],
      );
      return constraints.maxWidth < 600
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [heading, actions],
            )
          : Row(
              children: [
                Expanded(child: heading),
                actions,
              ],
            );
    },
  );
}
