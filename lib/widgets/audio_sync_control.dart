import 'package:flutter/material.dart';

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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
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
                style: TextStyle(fontSize: 12),
              ),
            ),
            Text(
              '${(value * 1000).round()} ms',
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12),
            ),
            IconButton(
              tooltip: 'همگام‌سازی پیش‌فرض سیستم',
              iconSize: 18,
              onPressed: busy ? null : () => apply(0),
              icon: const Icon(Icons.restart_alt),
            ),
          ],
        ),
        Slider(
          value: value,
          min: -3,
          max: 3,
          divisions: 120,
          onChanged: busy ? null : (v) => setState(() => value = v),
          onChangeEnd: busy ? null : apply,
        ),
        const Text(
          'اگر صدا عقب است، مقدار را منفی کن؛ اگر جلو است، مثبت کن.',
          style: TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
}
