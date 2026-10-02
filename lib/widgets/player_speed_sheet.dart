import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/platform_ui.dart';
import '../core/player_preferences.dart';
import '../core/theme.dart';

bool _compact(BuildContext context) =>
    !isAndroidTv && MediaQuery.sizeOf(context).shortestSide < 600;

double playerSpeedSheetWidth(BuildContext context) => math.min(
  MediaQuery.sizeOf(context).width - 24,
  _compact(context) ? 520 : 760,
);

/// Phone controls fit a short landscape screen; the footer stays reachable
/// while the optional subtitle timing controls scroll independently.
class PlayerSpeedSheet extends StatefulWidget {
  const PlayerSpeedSheet({
    super.key,
    required this.initial,
    required this.initialRate,
  });
  final SubtitlePreferences initial;
  final double initialRate;
  @override
  State<PlayerSpeedSheet> createState() => _PlayerSpeedSheetState();
}

class _PlayerSpeedSheetState extends State<PlayerSpeedSheet> {
  late SubtitlePreferences value = widget.initial;
  late double rate = widget.initialRate;

  @override
  Widget build(BuildContext context) {
    final compact = _compact(context);
    final media = MediaQuery.of(context);
    final available =
        media.size.height -
        media.padding.vertical -
        media.viewInsets.bottom -
        36;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(140, available * .9)),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 18,
            0,
            compact ? 12 : 18,
            compact ? 10 : 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.speed_rounded, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'تنظیم سرعت',
                      style: TextStyle(
                        fontSize: compact ? 16 : 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'بستن پنل',
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TimingCard(
                        title: 'سرعت ویدیو',
                        label: '${rate.toStringAsFixed(2)}×',
                        value: rate,
                        min: .5,
                        max: 4,
                        divisions: 70,
                        compact: compact,
                        onChanged: (v) => setState(() => rate = v),
                        step: .05,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 5,
                          runSpacing: 0,
                          children: [
                            for (final preset in [.5, 1.0, 1.25, 1.5, 2.0, 4.0])
                              TextButton(
                                onPressed: () => setState(() => rate = preset),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(44, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  foregroundColor: rate == preset
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white70,
                                ),
                                child: Text(
                                  '$preset×',
                                  textDirection: TextDirection.ltr,
                                  style: TextStyle(fontSize: compact ? 12 : 14),
                                ),
                              ),
                          ],
                        ),
                      ),
                      ExpansionTile(
                        key: const Key('subtitle-timing-expansion'),
                        initiallyExpanded: !compact,
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        dense: compact,
                        title: Text(
                          'زمان‌بندی زیرنویس',
                          style: TextStyle(fontSize: compact ? 13 : 16),
                        ),
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text(
                              'برای زیرنویس جدا؛ زیرنویس چسبیده قابل تغییر نیست.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          _TimingCard(
                            title: 'جابه‌جایی زمان زیرنویس',
                            label:
                                '${value.delay >= 0 ? '+' : ''}${value.delay.toStringAsFixed(1)} ثانیه',
                            value: value.delay,
                            min: -30,
                            max: 30,
                            divisions: 600,
                            compact: compact,
                            step: .1,
                            onChanged: (v) => setState(
                              () => value = value.copyWith(delay: v),
                            ),
                          ),
                          const SizedBox(height: 6),
                          _TimingCard(
                            title: 'سرعت زمان‌بندی زیرنویس',
                            label: '${value.timingScale.toStringAsFixed(2)}×',
                            value: value.timingScale,
                            min: .5,
                            max: 2,
                            divisions: 150,
                            compact: compact,
                            step: .01,
                            onChanged: (v) => setState(
                              () => value = value.copyWith(timingScale: v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        rate = 1;
                        value = value.copyWith(delay: 0, timingScale: 1);
                      }),
                      child: const Text('بازنشانی'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, (value, rate)),
                      child: const Text('اعمال سرعت'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimingCard extends StatelessWidget {
  const _TimingCard({
    required this.title,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.compact,
    required this.step,
    required this.onChanged,
  });
  final String title, label;
  final double value, min, max, step;
  final int divisions;
  final bool compact;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: MovieColors.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: EdgeInsets.all(compact ? 8 : 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 12 : 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(
            height: compact ? 40 : 48,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'کاهش $title',
                  onPressed: () =>
                      onChanged((value - step).clamp(min, max).toDouble()),
                  icon: const Icon(Icons.remove_rounded, size: 18),
                ),
                Expanded(
                  child: Slider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    divisions: divisions,
                    onChanged: onChanged,
                  ),
                ),
                IconButton(
                  tooltip: 'افزایش $title',
                  onPressed: () =>
                      onChanged((value + step).clamp(min, max).toDouble()),
                  icon: const Icon(Icons.add_rounded, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
