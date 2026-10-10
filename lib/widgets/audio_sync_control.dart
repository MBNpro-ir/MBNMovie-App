import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Live calibration is only applied on release: dragging never queues seeks.
class AudioSyncControl extends StatefulWidget {
  const AudioSyncControl({
    super.key,
    required this.initial,
    required this.onApply,
  });
  final double initial;
  final Future<void> Function(double) onApply;
  @override
  State<AudioSyncControl> createState() => _AudioSyncControlState();
}

class _AudioSyncControlState extends State<AudioSyncControl> {
  late double value = widget.initial.clamp(-3.0, 3.0);
  bool busy = false;
  @override
  void didUpdateWidget(covariant AudioSyncControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initial != oldWidget.initial && !busy) {
      value = widget.initial.clamp(-3.0, 3.0);
    }
  }

  Future<void> apply(double next) async {
    if (busy) return;
    setState(() {
      value = next;
      busy = true;
    });
    try {
      await widget.onApply(next);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).shortestSide < 600;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MovieColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.bluetooth_audio_rounded, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'هماهنگی صدا و تصویر',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${(value * 1000).round()} ms',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: compact ? 12 : 14,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  tooltip: 'بازنشانی هماهنگی',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed: busy ? null : () => apply(0),
                  icon: const Icon(Icons.restart_alt_rounded),
                ),
              ],
            ),
            SizedBox(
              height: compact ? 40 : 48,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'کاهش هماهنگی',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy
                        ? null
                        : () => apply((value - .05).clamp(-3, 3)),
                    icon: const Icon(Icons.remove_rounded, size: 18),
                  ),
                  Expanded(
                    child: Slider(
                      value: value,
                      min: -3,
                      max: 3,
                      divisions: 120,
                      onChanged: busy ? null : (v) => setState(() => value = v),
                      onChangeEnd: busy ? null : apply,
                    ),
                  ),
                  IconButton(
                    tooltip: 'افزایش هماهنگی',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy
                        ? null
                        : () => apply((value + .05).clamp(-3, 3)),
                    icon: const Icon(Icons.add_rounded, size: 18),
                  ),
                ],
              ),
            ),
            const Text(
              'اگر صدا عقب است، مقدار را منفی کن؛ اگر جلو است، مثبت کن.',
              style: TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
