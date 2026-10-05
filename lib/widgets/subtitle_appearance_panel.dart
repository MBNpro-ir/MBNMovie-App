import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/player_preferences.dart';
import '../core/platform_ui.dart';
import '../core/theme.dart';
import '../services/mbn_sync.dart';
import 'responsive_web_layout.dart';

class SubtitleAppearancePanel extends StatefulWidget {
  const SubtitleAppearancePanel({
    super.key,
    required this.initial,
    required this.onChanged,
    this.assAvailable = false,
    this.compactLayout,
    this.twoColumnLayout = false,
  });
  final SubtitlePreferences initial;
  final ValueChanged<SubtitlePreferences> onChanged;
  final bool assAvailable;
  final bool? compactLayout;
  final bool twoColumnLayout;
  @override
  State<SubtitleAppearancePanel> createState() =>
      _SubtitleAppearancePanelState();
}

class _SubtitleAppearancePanelState extends State<SubtitleAppearancePanel> {
  late SubtitlePreferences value = widget.initial;
  void change(SubtitlePreferences next) {
    setState(() => value = next);
    widget.onChanged(next);
    unawaited(() async {
      final prefs = await SharedPreferences.getInstance();
      await next.save(prefs);
      unawaited(MbnSync.instance.pushPreferencesThrottled());
    }());
  }

  Future<void> changeAss(bool enabled) async {
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('نمایش طراحی اصلی ASS'),
          content: const Text(
            'در این حالت فونت، رنگ، موقعیت و جلوه‌های طراحی‌شده توسط سازندهٔ زیرنویس نمایش داده می‌شود و تنظیمات ظاهری برنامه اعمال نمی‌شود. ادامه می‌دهی؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('فعال کردن'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    change(value.copyWith(originalAss: enabled));
  }

  Widget colors(
    String title,
    List<Color> colors,
    Color selected,
    SubtitlePreferences Function(Color) update,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title),
      const SizedBox(height: 5),
      Wrap(
        spacing: 7,
        children: [
          for (final color in colors)
            InkWell(
              onTap: () => change(update(color)),
              borderRadius: BorderRadius.circular(30),
              child: CircleAvatar(
                radius: 15,
                backgroundColor: color,
                child: selected == color
                    ? Icon(
                        Icons.check_rounded,
                        color: color.computeLuminance() > .6
                            ? Colors.black
                            : Colors.white,
                      )
                    : null,
              ),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final first = <Widget>[
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: value.fontFamily,
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'فونت فارسی',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'Vazirmatn', child: Text('وزیرمتن')),
                DropdownMenuItem(
                  value: 'NotoSansArabic',
                  child: Text('نوتو سنس فارسی'),
                ),
                DropdownMenuItem(
                  value: 'NotoNaskhArabic',
                  child: Text('نوتو نسخ فارسی'),
                ),
                DropdownMenuItem(value: 'MarkaziText', child: Text('مرکزی')),
                DropdownMenuItem(value: 'sans-serif', child: Text('ساده')),
                DropdownMenuItem(value: 'serif', child: Text('نسخ / سریف')),
              ],
              onChanged: (font) {
                if (font != null) change(value.copyWith(fontFamily: font));
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 98,
            child: DropdownButtonFormField<double>(
              value: value.size.clamp(10, 52).roundToDouble(),
              isExpanded: true,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'اندازه',
                isDense: true,
              ),
              items: [
                for (var size = 10; size <= 52; size++)
                  DropdownMenuItem(
                    value: size.toDouble(),
                    child: Text('$size'),
                  ),
              ],
              onChanged: (size) {
                if (size != null) change(value.copyWith(size: size));
              },
            ),
          ),
        ],
      ),
      _AppearanceSlider(
        label: 'فاصله خطوط',
        value: value.lineHeight,
        min: 1,
        max: 2,
        onChanged: (v) => change(value.copyWith(lineHeight: v)),
      ),
      _AppearanceSlider(
        label: 'فاصله از پایین',
        value: value.bottomPadding,
        min: 0,
        max: 1000,
        onChanged: (v) => change(value.copyWith(bottomPadding: v)),
      ),
      const SizedBox(height: 12),
      colors(
        'رنگ متن',
        const [
          Colors.white,
          Color(0xFFFFE66D),
          Color(0xFFFFD600),
          Color(0xFFFFA000),
          Color(0xFFFF6D00),
          Color(0xFFFF3D00),
          Color(0xFF8FE9FF),
          Color(0xFF00E5FF),
          Color(0xFF76FF03),
          Color(0xFFFFB3C6),
          Color(0xFFFF4081),
        ],
        value.color,
        (c) => value.copyWith(color: c),
      ),
    ];
    final second = <Widget>[
      _AppearanceSlider(
        label: 'تیرگی پس‌زمینه',
        value: value.backgroundOpacity,
        min: 0,
        max: 1,
        onChanged: (v) => change(value.copyWith(backgroundOpacity: v)),
      ),
      _AppearanceSlider(
        label: 'گردی گوشه‌ها',
        value: value.cornerRadius,
        min: 0,
        max: 24,
        onChanged: (v) => change(value.copyWith(cornerRadius: v)),
      ),
      const SizedBox(height: 12),
      colors(
        'رنگ پس‌زمینه',
        const [
          Colors.black,
          Color(0xFF3A3F4B),
          Color(0xFFFF7A1A),
          Color(0xFF8D6BFF),
          Color(0xFF0E7C7B),
        ],
        value.backgroundColor,
        (c) => value.copyWith(backgroundColor: c),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: const Text('متن ضخیم'),
        value: value.bold,
        onChanged: (v) => change(value.copyWith(bold: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        visualDensity: VisualDensity.compact,
        title: const Text('سایه و حاشیه برای خوانایی'),
        value: value.shadow,
        onChanged: (v) => change(value.copyWith(shadow: v)),
      ),
      if (widget.assAvailable)
        SwitchListTile(
          key: const Key('original-ass-switch'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('طراحی اصلی ASS'),
          subtitle: Text(
            value.originalAss
                ? 'ظاهر سازندهٔ زیرنویس'
                : 'نمایش ساده با ظاهر برنامه',
          ),
          value: value.originalAss,
          onChanged: changeAss,
        ),
    ];
    Widget appearanceControl(Widget child) {
      if (child.key == const Key('original-ass-switch')) return child;
      return AbsorbPointer(
        absorbing: widget.assAvailable && value.originalAss,
        child: Opacity(
          opacity: widget.assAvailable && value.originalAss ? .4 : 1,
          child: child,
        ),
      );
    }

    Widget pane(List<Widget> children) => Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.twoColumnLayout ? 4 : 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children.map(appearanceControl).toList(),
        ),
      ),
    );
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.compactLayout ?? (kIsWeb || !isLargeScreenDevice))
              SubtitlePanelToolbar(
                singleRow: widget.twoColumnLayout,
                onReset: () => change(
                  SubtitlePreferences(
                    delay: value.delay,
                    timingScale: value.timingScale,
                  ),
                ),
                onSave: () => Navigator.pop(context, value),
              )
            else
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'تنظیمات ظاهر زیرنویس',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => change(
                      SubtitlePreferences(
                        delay: value.delay,
                        timingScale: value.timingScale,
                      ),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('پیش‌فرض'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, value),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('ذخیره'),
                  ),
                ],
              ),
            const Divider(),
            Flexible(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: widget.twoColumnLayout || constraints.maxWidth >= 600
                      ? Row(
                          key: const Key('subtitle-appearance-columns'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [pane(first), pane(second)],
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ...first,
                            ...second,
                          ].map(appearanceControl).toList(),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Retained for compatibility with older golden/widget references.
class _AppearanceSlider extends StatelessWidget {
  const _AppearanceSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: MovieColors.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: MovieColors.orange.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    child: Text(
                      value.toStringAsFixed(1),
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: MovieColors.orange,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 30,
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
