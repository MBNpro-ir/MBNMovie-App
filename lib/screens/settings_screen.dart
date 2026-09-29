import 'dart:async';
import 'dart:io';

import '../services/accessibility_service.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/player_preferences.dart';
import '../core/theme.dart';
import '../core/title_language.dart';
import '../services/device_bridge.dart';
import '../services/mbn_sync.dart';
import '../services/external_apps.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  static const _streamers = <String, String>{
    PlaybackPreferenceStore.askEveryTime: 'هر بار از من بپرس',
    PlaybackPreferenceStore.miracast: 'Wireless Display / Miracast',
    'googleCast': 'Chromecast و Google TV',
    'dlna': 'تلویزیون DLNA',
    'lgWebOs': 'LG webOS',
    'airPlay': 'Apple TV و AirPlay',
    'fireTv': 'Amazon Fire TV',
    'rokuXbox': 'Roku یا Xbox',
  };
  static const _fonts = <String, String>{
    'Vazirmatn': 'وزیرمتن',
    'NotoSansArabic': 'نوتو سنس فارسی',
    'NotoNaskhArabic': 'نوتو نسخ فارسی',
    'MarkaziText': 'مرکزی',
    'sans-serif': 'ساده',
    'serif': 'نسخ / سریف',
  };
  static const _textColors = <Color>[
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
  ];
  static const _backgroundColors = <Color>[
    Colors.black,
    Color(0xFF3A3F4B),
    Color(0xFFFF7A1A),
    Color(0xFF8D6BFF),
    Color(0xFF0E7C7B),
  ];

  static String _colorName(Color color) => switch (color.toARGB32()) {
    0xFFFFFFFF => 'سفید',
    0xFFFFE66D => 'زرد روشن',
    0xFFFFD600 => 'زرد',
    0xFFFFA000 => 'کهربایی',
    0xFFFF6D00 => 'نارنجی',
    0xFFFF3D00 => 'نارنجی تند',
    0xFF8FE9FF => 'آبی روشن',
    0xFF00E5FF => 'فیروزه‌ای',
    0xFF76FF03 => 'سبز روشن',
    0xFFFFB3C6 => 'صورتی روشن',
    0xFFFF4081 => 'صورتی',
    0xFF000000 => 'مشکی',
    0xFF3A3F4B => 'خاکستری تیره',
    0xFFFF7A1A => 'نارنجی پس‌زمینه',
    0xFF8D6BFF => 'بنفش',
    0xFF0E7C7B => 'سبز تیره',
    final value =>
      '#${value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
  };

  bool _loading = true;
  bool _syncSettingsEnabled = true;
  double _volume = 100;
  double _rate = 1;
  bool _fitCover = false;
  bool _englishTitles = false;
  bool _customBrightness = false;
  double _brightness = .5;
  String _defaultPlayer = PlaybackPreferenceStore.askEveryTime;
  String _defaultStreamer = PlaybackPreferenceStore.askEveryTime;
  SubtitlePreferences _subtitle = const SubtitlePreferences();

  Map<String, String> get _players => {
    PlaybackPreferenceStore.askEveryTime: 'هر بار از من بپرس',
    PlaybackPreferenceStore.internalPlayer: 'پلیر داخلی (پیشنهادی)',
    ExternalVideoPlayer.vlc.name: 'VLC',
    if (Platform.isAndroid) ExternalVideoPlayer.mxPlayer.name: 'MX Player',
    if (Platform.isAndroid)
      ExternalVideoPlayer.mxPlayerPro.name: 'MX Player Pro',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final player = prefs.getString(PlaybackPreferenceStore.defaultPlayerKey);
    final streamer = prefs.getString(
      PlaybackPreferenceStore.defaultStreamerKey,
    );
    final brightness = prefs.getDouble('player_screen_brightness');
    if (!mounted) return;
    setState(() {
      _volume = (prefs.getDouble('player_volume') ?? 100).clamp(0, 100);
      _rate = (prefs.getDouble('player_rate') ?? 1).clamp(.5, 4.0);
      _fitCover = prefs.getBool('player_fit_cover') ?? false;
      _englishTitles = prefs.getBool(TitleLanguage.preferenceKey) ?? false;
      _customBrightness = brightness != null;
      _brightness = (brightness ?? .5).clamp(0, 1);
      _defaultPlayer = _players.containsKey(player)
          ? player!
          : PlaybackPreferenceStore.askEveryTime;
      _defaultStreamer = _streamers.containsKey(streamer)
          ? streamer!
          : PlaybackPreferenceStore.askEveryTime;
      _subtitle = SubtitlePreferences.fromStore(prefs);
      _syncSettingsEnabled = prefs.getBool('sync_settings_enabled') ?? true;
      _loading = false;
    });
  }

  Future<void> _savePlayer() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('player_volume', _volume);
    await prefs.setDouble('player_rate', _rate);
    await prefs.setBool('player_fit_cover', _fitCover);
    if (_customBrightness) {
      await prefs.setDouble('player_screen_brightness', _brightness);
      if (Platform.isAndroid) {
        await DeviceBridge.setScreenBrightness(_brightness);
      }
    } else {
      await prefs.remove('player_screen_brightness');
      if (Platform.isAndroid) await DeviceBridge.setScreenBrightness(null);
    }
    await MbnSync.instance.pushPreferences();
  }

  Future<void> _saveSubtitle(SubtitlePreferences value) async {
    setState(() => _subtitle = value);
    await value.save(await SharedPreferences.getInstance());
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> _reset() async {
    final prefs = await SharedPreferences.getInstance();
    const subtitle = SubtitlePreferences();
    setState(() {
      _volume = 100;
      _rate = 1;
      _fitCover = false;
      _englishTitles = false;
      _customBrightness = false;
      _brightness = .5;
      _defaultPlayer = PlaybackPreferenceStore.askEveryTime;
      _defaultStreamer = PlaybackPreferenceStore.askEveryTime;
      _syncSettingsEnabled = true;
      _subtitle = subtitle;
    });
    await prefs.setDouble('player_volume', 100);
    await prefs.setDouble('player_rate', 1);
    await prefs.setBool('player_fit_cover', false);
    await TitleLanguage.setEnglish(false);
    await prefs.remove('player_screen_brightness');
    await prefs.setString(
      PlaybackPreferenceStore.defaultPlayerKey,
      PlaybackPreferenceStore.askEveryTime,
    );
    await prefs.setString(
      PlaybackPreferenceStore.defaultStreamerKey,
      PlaybackPreferenceStore.askEveryTime,
    );
    await subtitle.save(prefs);
    await prefs.setBool('sync_settings_enabled', true);
    if (Platform.isAndroid) await DeviceBridge.setScreenBrightness(null);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('تنظیمات'),
      actions: [
        IconButton(
          onPressed: _loading ? null : _reset,
          icon: const Icon(Icons.restart_alt_rounded),
          tooltip: 'بازنشانی تنظیمات',
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _scrollController,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      constraints.maxWidth >= 840 ? 24 : 12,
                      12,
                      constraints.maxWidth >= 840 ? 24 : 12,
                      30,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: MovieColors.orange.withValues(alpha: .08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: MovieColors.orange.withValues(alpha: .2),
                            ),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                color: MovieColors.orange,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'تنظیمات پخش، انتقال تصویر و ظاهر زیرنویس در همین صفحه ذخیره می‌شوند.',
                                ),
                              ),
                            ],
                          ),
                        ),
                        _section(
                          icon: Icons.cloud_sync_rounded,
                          title: 'همگام‌سازی ابری',
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'همگام‌سازی همیشگی تنظیمات برنامه با سرور',
                              ),
                              subtitle: const Text(
                                'در صورت غیرفعال بودن، تنظیمات پلیر و زیرنویس فقط در این دستگاه ذخیره می‌شوند و روی سرور بازنویسی نخواهند شد.',
                              ),
                              value: _syncSettingsEnabled,
                              onChanged: (value) async {
                                setState(() => _syncSettingsEnabled = value);
                                final prefs =
                                    await SharedPreferences.getInstance();
                                await prefs.setBool(
                                  'sync_settings_enabled',
                                  value,
                                );
                                if (value) {
                                  await MbnSync.instance.pushPreferences();
                                }
                              },
                            ),
                          ],
                        ),
                        _section(
                          icon: Icons.accessibility_new_rounded,
                          title: 'دسترسی‌پذیری و مقیاس نمایش (Accessibility)',
                          children: [
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: MovieColors.surfaceHigh.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: MovieColors.cyan.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.sync_alt_rounded,
                                    color: MovieColors.cyan,
                                    size: 22,
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '📱💻 همگام‌سازی ابری تفکیک‌شده: تنظیمات ابعاد و مقیاس برای گوشی و کامپیوتر به‌صورت جداگانه در سرور ذخیره می‌شوند تا تغییر سایز گوشی روی مانیتور کامپیوتر اثری نداشته باشد.',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ListenableBuilder(
                              listenable: AccessibilityService.instance,
                              builder: (context, _) {
                                final access = AccessibilityService.instance;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // UI Scale
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'مقیاس کلی برنامه (اندازه همهٔ بخش‌ها و آیکون‌ها)',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                              SizedBox(height: 2),
                                              Text(
                                                'اگر عناصر در گوشی خیلی بزرگ هستند، مقدار فشرده (۸۰٪ یا ۸۵٪) را انتخاب کنید.',
                                                style: TextStyle(
                                                  color: MovieColors.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: MovieColors.orange.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: MovieColors.orange.withValues(
                                                alpha: 0.4,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            '${(access.uiScale * 100).round()}٪',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: MovieColors.orange,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.zoom_out_rounded,
                                          size: 20,
                                          color: MovieColors.muted,
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: access.uiScale,
                                            min: 0.70,
                                            max: 1.30,
                                            divisions: 12,
                                            label:
                                                '${(access.uiScale * 100).round()}٪',
                                            onChanged: (val) =>
                                                access.setUiScale(val),
                                          ),
                                        ),
                                        const Icon(
                                          Icons.zoom_in_rounded,
                                          size: 20,
                                          color: MovieColors.muted,
                                        ),
                                      ],
                                    ),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _ScaleChip(
                                          label: '۸۰٪ بسیار فشرده',
                                          value: 0.80,
                                          current: access.uiScale,
                                          onSelect: access.setUiScale,
                                        ),
                                        _ScaleChip(
                                          label: '۸۵٪ بهینه گوشی',
                                          value: 0.85,
                                          current: access.uiScale,
                                          onSelect: access.setUiScale,
                                        ),
                                        _ScaleChip(
                                          label: '۹۰٪ کمی فشرده',
                                          value: 0.90,
                                          current: access.uiScale,
                                          onSelect: access.setUiScale,
                                        ),
                                        _ScaleChip(
                                          label: '۱۰۰٪ استاندارد',
                                          value: 1.00,
                                          current: access.uiScale,
                                          onSelect: access.setUiScale,
                                        ),
                                        _ScaleChip(
                                          label: '۱۱۰٪ بزرگ',
                                          value: 1.10,
                                          current: access.uiScale,
                                          onSelect: access.setUiScale,
                                        ),
                                        _ScaleChip(
                                          label: '۱۲۰٪ خیلی بزرگ',
                                          value: 1.20,
                                          current: access.uiScale,
                                          onSelect: access.setUiScale,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),

                                    // Text Scale
                                    Row(
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'اندازه متون و قلم‌ها',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${(access.textScale * 100).round()}٪',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.text_fields_rounded,
                                          size: 20,
                                          color: MovieColors.muted,
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: access.textScale,
                                            min: 0.80,
                                            max: 1.40,
                                            divisions: 12,
                                            label:
                                                '${(access.textScale * 100).round()}٪',
                                            onChanged: (val) =>
                                                access.setTextScale(val),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),

                                    // Density
                                    DropdownButtonFormField<DensityMode>(
                                      initialValue: access.densityMode,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'تراکم چیدمان و فاصله‌ها (Density)',
                                        helperText:
                                            'تنظیم فاصله بین ردیف‌ها و حاشیه‌های کلیدها',
                                      ),
                                      items: DensityMode.values
                                          .map(
                                            (mode) => DropdownMenuItem(
                                              value: mode,
                                              child: Text(mode.label),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (mode) {
                                        if (mode != null) access.setDensity(mode);
                                      },
                                    ),
                                    const SizedBox(height: 14),

                                    // Switches
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'کاهش انیمیشن‌ها و افکت‌های حرکتی (Reduce Motion)',
                                      ),
                                      subtitle: const Text(
                                        'ساده‌سازی ترنزیشن‌ها برای سرعت بالاتر و افراد حساس به حرکت',
                                      ),
                                      value: access.reduceMotion,
                                      onChanged: (val) =>
                                          access.setReduceMotion(val),
                                    ),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'افزایش کنتراست و خطوط تم تیره (High Contrast)',
                                      ),
                                      subtitle: const Text(
                                        'پررنگ‌تر کردن مرزها و کارت‌ها جهت دید بهتر',
                                      ),
                                      value: access.highContrast,
                                      onChanged: (val) =>
                                          access.setHighContrast(val),
                                    ),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'نمایش متون پررنگ (Bold Text)',
                                      ),
                                      subtitle: const Text(
                                        'افزایش ضخامت نوشته‌ها برای سهولت در خواندن',
                                      ),
                                      value: access.boldText,
                                      onChanged: (val) =>
                                          access.setBoldText(val),
                                    ),
                                    SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'بازخورد لرزشی کلیدها (Haptic Feedback)',
                                      ),
                                      subtitle: const Text(
                                        'لرزش بسیار خفیف هنگام لمس بخش‌ها',
                                      ),
                                      value: access.haptics,
                                      onChanged: (val) => access.setHaptics(val),
                                    ),
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: OutlinedButton.icon(
                                        icon: const Icon(
                                          Icons.restart_alt_rounded,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'بازنشانی دسترسی‌پذیری به مقادیر پیش‌فرض',
                                        ),
                                        onPressed: () async {
                                          await access.resetToDefaults();
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'تنظیمات دسترسی‌پذیری بازنشانی شدند.',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                        _section(
                          icon: Icons.translate_rounded,
                          title: 'عنوان فیلم‌ها و سریال‌ها',
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('نمایش عنوان‌های اصلی به انگلیسی'),
                              subtitle: const Text(
                                'جست‌وجو با نام فارسی و انگلیسی در هر دو حالت کار می‌کند.',
                              ),
                              value: _englishTitles,
                              onChanged: (value) async {
                                setState(() => _englishTitles = value);
                                await TitleLanguage.setEnglish(value);
                              },
                            ),
                          ],
                        ),
                        _section(
                          icon: Icons.route_rounded,
                          title: 'پخش و انتقال پیش‌فرض',
                          children: [
                            DropdownButtonFormField<String>(
                              key: const Key('default-player-setting'),
                              initialValue: _defaultPlayer,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'پخش‌کنندهٔ پیش‌فرض',
                                helperText:
                                    'با انتخاب پیش‌فرض، منوی انتخاب پلیر نمایش داده نمی‌شود.',
                              ),
                              items: [
                                for (final entry in _players.entries)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                setState(() => _defaultPlayer = value);
                                await PlaybackPreferenceStore.setDefaultPlayer(
                                  value,
                                );
                              },
                            ),
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              key: const Key('default-streamer-setting'),
                              initialValue: _defaultStreamer,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'روش انتقال تصویر پیش‌فرض',
                                helperText:
                                    'در بخش تلویزیون، مستقیماً همین روش باز می‌شود.',
                              ),
                              items: [
                                for (final entry in _streamers.entries)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                setState(() => _defaultStreamer = value);
                                await PlaybackPreferenceStore.setDefaultStreamer(
                                  value,
                                );
                              },
                            ),
                          ],
                        ),
                        _section(
                          icon: Icons.play_circle_outline_rounded,
                          title: 'پلیر',
                          children: [
                            _slider(
                              label: 'صدای پیش‌فرض',
                              value: _volume,
                              min: 0,
                              max: 100,
                              suffix: '${_volume.round()}٪',
                              onChanged: (value) {
                                setState(() => _volume = value);
                                _savePlayer();
                              },
                            ),
                            _slider(
                              label: 'سرعت پخش',
                              value: _rate.clamp(.5, 4.0),
                              min: .5,
                              max: 4.0,
                              divisions: 70,
                              suffix: '${_rate.toStringAsFixed(2)}×',
                              onChanged: (value) {
                                setState(() => _rate = (value * 100).round() / 100.0);
                                _savePlayer();
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  for (final speed in [0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0])
                                    ChoiceChip(
                                      label: Text('${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}×'),
                                      selected: (_rate - speed).abs() < 0.04,
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() => _rate = speed);
                                          _savePlayer();
                                        }
                                      },
                                    ),
                                ],
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('پر کردن صفحه با تصویر'),
                              subtitle: const Text(
                                'ممکن است بخش کوچکی از لبه‌های تصویر بریده شود.',
                              ),
                              value: _fitCover,
                              onChanged: (value) {
                                setState(() => _fitCover = value);
                                _savePlayer();
                              },
                            ),
                            if (Platform.isAndroid) ...[
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('نور اختصاصی پلیر'),
                                subtitle: const Text(
                                  'در حالت خاموش، نور سیستم استفاده می‌شود.',
                                ),
                                value: _customBrightness,
                                onChanged: (value) {
                                  setState(() => _customBrightness = value);
                                  _savePlayer();
                                },
                              ),
                              if (_customBrightness)
                                _slider(
                                  label: 'نور صفحه در پلیر',
                                  value: _brightness,
                                  min: 0,
                                  max: 1,
                                  suffix: '${(_brightness * 100).round()}٪',
                                  onChanged: (value) {
                                    setState(() => _brightness = value);
                                    _savePlayer();
                                  },
                                ),
                            ],
                          ],
                        ),
                        _section(
                          icon: Icons.closed_caption_rounded,
                          title: 'زیرنویس',
                          wideLeadCount: 2,
                          children: [
                            _subtitlePreview(),
                            const SizedBox(height: 18),
                            DropdownButtonFormField<String>(
                              initialValue: _subtitle.fontFamily,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'فونت',
                              ),
                              items: [
                                for (final entry in _fonts.entries)
                                  DropdownMenuItem(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  _saveSubtitle(
                                    _subtitle.copyWith(fontFamily: value),
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 12),
                            _slider(
                              label: 'اندازه متن',
                              value: _subtitle.size,
                              min: 10,
                              max: 52,
                              suffix: _subtitle.size.round().toString(),
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(size: value),
                              ),
                            ),
                            _slider(
                              label: 'فاصله خطوط',
                              value: _subtitle.lineHeight,
                              min: 1,
                              max: 2,
                              suffix: _subtitle.lineHeight.toStringAsFixed(2),
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(lineHeight: value),
                              ),
                            ),
                            _slider(
                              label: 'فاصله از پایین',
                              value: _subtitle.bottomPadding,
                              min: 0,
                              max: 1000,
                              suffix: _subtitle.bottomPadding
                                  .round()
                                  .toString(),
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(bottomPadding: value),
                              ),
                            ),
                            _slider(
                              label: 'تیرگی پس‌زمینه',
                              value: _subtitle.backgroundOpacity,
                              min: 0,
                              max: 1,
                              suffix:
                                  '${(_subtitle.backgroundOpacity * 100).round()}٪',
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(backgroundOpacity: value),
                              ),
                            ),
                            _slider(
                              label: 'گردی گوشه‌ها',
                              value: _subtitle.cornerRadius,
                              min: 0,
                              max: 24,
                              suffix: _subtitle.cornerRadius.round().toString(),
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(cornerRadius: value),
                              ),
                            ),
                            _slider(
                              label: 'هماهنگی زمانی زیرنویس',
                              value: _subtitle.delay,
                              min: -10,
                              max: 10,
                              divisions: 80,
                              suffix: '${_subtitle.delay.toStringAsFixed(2)}s',
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(delay: value),
                              ),
                            ),
                            _slider(
                              label: 'سرعت زمان‌بندی زیرنویس',
                              value: _subtitle.timingScale,
                              min: .8,
                              max: 1.2,
                              divisions: 80,
                              suffix:
                                  '${_subtitle.timingScale.toStringAsFixed(3)}×',
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(timingScale: value),
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('متن ضخیم'),
                              value: _subtitle.bold,
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(bold: value),
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('سایه و حاشیه برای خوانایی'),
                              value: _subtitle.shadow,
                              onChanged: (value) => _saveSubtitle(
                                _subtitle.copyWith(shadow: value),
                              ),
                            ),
                            _palette(
                              'رنگ متن',
                              _textColors,
                              _subtitle.color,
                              (color) => _saveSubtitle(
                                _subtitle.copyWith(color: color),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _palette(
                              'رنگ پس‌زمینه',
                              _backgroundColors,
                              _subtitle.backgroundColor,
                              (color) => _saveSubtitle(
                                _subtitle.copyWith(backgroundColor: color),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
  );

  Widget _section({
    required IconData icon,
    required String title,
    required List<Widget> children,
    int wideLeadCount = 0,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: MovieColors.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 760) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                );
              }
              final lead = children.take(wideLeadCount).toList();
              final rest = children
                  .skip(wideLeadCount)
                  .where((child) => child is! SizedBox);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...lead,
                  if (lead.isNotEmpty) const SizedBox(height: 10),
                  Wrap(
                    spacing: 18,
                    runSpacing: 14,
                    children: [
                      for (final child in rest)
                        SizedBox(
                          width: (constraints.maxWidth - 18) / 2,
                          child: child,
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String suffix,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(suffix, textDirection: TextDirection.ltr),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    ],
  );

  Widget _palette(
    String label,
    List<Color> colors,
    Color selected,
    ValueChanged<Color> onChanged,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 9),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final color in colors)
            Semantics(
              button: true,
              selected: color == selected,
              label:
                  'رنگ زیرنویس ${_colorName(color)}${color == selected ? '، انتخاب‌شده' : ''}',
              child: InkWell(
                onTap: () => onChanged(color),
                borderRadius: BorderRadius.circular(30),
                child: Padding(
                  // 36px circle + padding = >=48px touch target.
                  padding: const EdgeInsets.all(6),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: color,
                    child: color == selected
                        ? ExcludeSemantics(
                            child: Icon(
                              Icons.check_rounded,
                              color: color.computeLuminance() > .6
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    ],
  );

  Widget _subtitlePreview() => Semantics(
    label: 'پیش‌نمایش دو خطی زیرنویس',
    child: AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF303747), Color(0xFF10131B)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewScale = (constraints.maxWidth / 700)
                  .clamp(.52, 1.0)
                  .toDouble();
              final bottom = (_subtitle.bottomPadding * previewScale).clamp(
                10.0,
                constraints.maxHeight * .42,
              );
              return Stack(
                fit: StackFit.expand,
                children: [
                  const Center(
                    child: Icon(
                      Icons.movie_filter_rounded,
                      size: 74,
                      color: Colors.white10,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: bottom,
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14 * previewScale,
                          vertical: 7 * previewScale,
                        ),
                        decoration: BoxDecoration(
                          color: _subtitle.backgroundColor.withValues(
                            alpha: _subtitle.backgroundOpacity,
                          ),
                          borderRadius: BorderRadius.circular(
                            _subtitle.cornerRadius * previewScale,
                          ),
                        ),
                        child: Text(
                          'این یک پیش‌نمایش زیرنویس فارسی است\nتغییرات خط دوم هم‌زمان نمایش داده می‌شود',
                          key: const Key('subtitle-two-line-preview'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontFamily: _subtitle.fontFamily,
                            fontSize: _subtitle.size * previewScale,
                            height: _subtitle.lineHeight,
                            fontWeight: _subtitle.bold
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: _subtitle.color,
                            shadows: _subtitle.shadow
                                ? const [
                                    Shadow(
                                      color: Colors.black,
                                      blurRadius: 5,
                                      offset: Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    top: 10,
                    right: 12,
                    child: Text(
                      'پیش‌نمایش زنده',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _ScaleChip extends StatelessWidget {
  const _ScaleChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onSelect,
  });

  final String label;
  final double value;
  final double current;
  final ValueChanged<double> onSelect;

  @override
  Widget build(BuildContext context) {
    final selected = (current - value).abs() < 0.01;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      selected: selected,
      onSelected: (_) => onSelect(value),
      selectedColor: MovieColors.orange.withValues(alpha: 0.25),
      labelStyle: TextStyle(
        color: selected ? MovieColors.orange : Colors.white70,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

