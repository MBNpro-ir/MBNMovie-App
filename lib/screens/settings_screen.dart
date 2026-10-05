import 'dart:async';
import '../core/app_platform.dart';

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
  bool _syncingFromServer = false;
  bool _syncSettingsEnabled = true;
  double _volume = 100;
  double _rate = 1;
  bool _fitCover = false;
  bool _englishTitles = false;
  bool _customBrightness = false;
  double _brightness = .5;
  String _defaultPlayer = PlaybackPreferenceStore.askEveryTime;
  String _defaultStreamer = PlaybackPreferenceStore.askEveryTime;
  SubtitlePreferences _subtitle = SubtitlePreferences.withPlatformDefaults();

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
      _englishTitles = TitleLanguage.english;
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
    final subtitle = SubtitlePreferences.withPlatformDefaults();
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
    await TitleLanguage.setEnglish(true);
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

  Future<void> _pullFromServer() async {
    setState(() => _syncingFromServer = true);
    try {
      final success = await MbnSync.instance.pullAndApplyPreferences(
        force: true,
      );
      if (!mounted) return;
      if (success) {
        await _load();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تنظیمات با موفقیت از سرور دریافت و اعمال شدند.'),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تنظیمات جدیدی در سرور یافت نشد یا اینترنت متصل نیست.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('خطا در دریافت تنظیمات از سرور.')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncingFromServer = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('تنظیمات'),
      actions: [
        IconButton(
          onPressed: _loading || _syncingFromServer ? null : _pullFromServer,
          icon: _syncingFromServer
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_download_rounded),
          tooltip: 'دریافت تنظیمات از سرور',
        ),
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
            builder: (context, constraints) => ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: EdgeInsets.fromLTRB(
                        constraints.maxWidth >= 840 ? 24 : 14,
                        16,
                        constraints.maxWidth >= 840 ? 24 : 14,
                        32,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: MovieColors.surfaceHigh.withValues(
                                alpha: 0.5,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: MovieColors.orange.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: MovieColors.orange.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.cloud_sync_rounded,
                                    color: MovieColors.orange,
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'همگام‌سازی ابری تنظیمات',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'اگر تنظیمات شما از سرور اعمال نشده، می‌توانید همین حالا دوباره دریافت کنید.',
                                        style: TextStyle(
                                          color: MovieColors.muted,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: MovieColors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                  onPressed: _loading || _syncingFromServer
                                      ? null
                                      : _pullFromServer,
                                  icon: _syncingFromServer
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.cloud_download_rounded,
                                          size: 18,
                                        ),
                                  label: const Text('دریافت از سرور'),
                                ),
                              ],
                            ),
                          ),
                          // 1. پخش و انتقال پیش‌فرض
                          _section(
                            icon: Icons.route_rounded,
                            title: 'پخش و انتقال پیش‌فرض',
                            subtitle:
                                'انتخاب پلیر داخلی یا خارجی و روش ارسال تصویر به تلویزیون',
                            children: [
                              _responsiveRow(
                                first: DropdownButtonFormField<String>(
                                  key: const Key('default-player-setting'),
                                  value: _defaultPlayer,
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
                                second: DropdownButtonFormField<String>(
                                  key: const Key('default-streamer-setting'),
                                  value: _defaultStreamer,
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
                              ),
                            ],
                          ),

                          // 2. پلیر
                          _section(
                            icon: Icons.play_circle_outline_rounded,
                            title: 'پلیر',
                            subtitle: 'تنظیمات صدا، سرعت پخش و رفتار تصویر',
                            children: [
                              _responsiveRow(
                                first: _slider(
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
                                second: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _slider(
                                      label: 'سرعت پخش',
                                      value: _rate.clamp(.5, 4.0),
                                      min: .5,
                                      max: 4.0,
                                      divisions: 70,
                                      suffix: '${_rate.toStringAsFixed(2)}×',
                                      onChanged: (value) {
                                        setState(
                                          () => _rate =
                                              (value * 100).round() / 100.0,
                                        );
                                        _savePlayer();
                                      },
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        for (final speed in [
                                          0.75,
                                          1.0,
                                          1.25,
                                          1.5,
                                          1.75,
                                          2.0,
                                          2.5,
                                          3.0,
                                          4.0,
                                        ])
                                          ChoiceChip(
                                            label: Text(
                                              '${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}×',
                                            ),
                                            selected:
                                                (_rate - speed).abs() < 0.04,
                                            onSelected: (selected) {
                                              if (selected) {
                                                setState(() => _rate = speed);
                                                _savePlayer();
                                              }
                                            },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
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
                                const Divider(height: 20),
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

                          // 3. زیرنویس
                          _section(
                            icon: Icons.closed_caption_rounded,
                            title: 'زیرنویس',
                            subtitle:
                                'شخصی‌سازی ظاهر، فونت، اندازه و موقعیت زیرنویس',
                            children: [
                              _subtitlePreview(),
                              const SizedBox(height: 18),
                              _responsiveRow(
                                first: DropdownButtonFormField<String>(
                                  value: _subtitle.fontFamily,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'فونت زیرنویس',
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
                                second: _slider(
                                  label: 'اندازه متن',
                                  value: _subtitle.size,
                                  min: 10,
                                  max: 52,
                                  suffix: _subtitle.size.round().toString(),
                                  onChanged: (value) => _saveSubtitle(
                                    _subtitle.copyWith(size: value),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _responsiveRow(
                                first: _slider(
                                  label: 'فاصله خطوط',
                                  value: _subtitle.lineHeight,
                                  min: 1,
                                  max: 2,
                                  suffix: _subtitle.lineHeight.toStringAsFixed(
                                    2,
                                  ),
                                  onChanged: (value) => _saveSubtitle(
                                    _subtitle.copyWith(lineHeight: value),
                                  ),
                                ),
                                second: _slider(
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
                              ),
                              const SizedBox(height: 12),
                              _responsiveRow(
                                first: _slider(
                                  label: 'تیرگی پس‌زمینه',
                                  value: _subtitle.backgroundOpacity,
                                  min: 0,
                                  max: 1,
                                  suffix:
                                      '${(_subtitle.backgroundOpacity * 100).round()}٪',
                                  onChanged: (value) => _saveSubtitle(
                                    _subtitle.copyWith(
                                      backgroundOpacity: value,
                                    ),
                                  ),
                                ),
                                second: _slider(
                                  label: 'گردی گوشه‌ها',
                                  value: _subtitle.cornerRadius,
                                  min: 0,
                                  max: 24,
                                  suffix: _subtitle.cornerRadius
                                      .round()
                                      .toString(),
                                  onChanged: (value) => _saveSubtitle(
                                    _subtitle.copyWith(cornerRadius: value),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _responsiveRow(
                                first: _slider(
                                  label: 'هماهنگی زمانی زیرنویس',
                                  value: _subtitle.delay,
                                  min: -10,
                                  max: 10,
                                  divisions: 80,
                                  suffix:
                                      '${_subtitle.delay.toStringAsFixed(2)}s',
                                  onChanged: (value) => _saveSubtitle(
                                    _subtitle.copyWith(delay: value),
                                  ),
                                ),
                                second: _slider(
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
                              ),
                              const SizedBox(height: 12),
                              _responsiveRow(
                                first: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('متن ضخیم'),
                                  value: _subtitle.bold,
                                  onChanged: (value) => _saveSubtitle(
                                    _subtitle.copyWith(bold: value),
                                  ),
                                ),
                                second: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'سایه و حاشیه برای خوانایی',
                                  ),
                                  value: _subtitle.shadow,
                                  onChanged: (value) => _saveSubtitle(
                                    _subtitle.copyWith(shadow: value),
                                  ),
                                ),
                              ),
                              const Divider(height: 28),
                              _palette(
                                'رنگ متن',
                                _textColors,
                                _subtitle.color,
                                (color) => _saveSubtitle(
                                  _subtitle.copyWith(color: color),
                                ),
                              ),
                              const SizedBox(height: 16),
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

                          // 4. دسترسی‌پذیری و مقیاس نمایش
                          _section(
                            icon: Icons.accessibility_new_rounded,
                            title: 'دسترسی‌پذیری و مقیاس نمایش (Accessibility)',
                            subtitle:
                                'تنظیم ابعاد کل برنامه، اندازه فونت‌ها و گزینه‌های دیداری',
                            children: [
                              Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: MovieColors.surfaceHigh.withValues(
                                    alpha: 0.6,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: MovieColors.cyan.withValues(
                                      alpha: 0.3,
                                    ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
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
                                              color: MovieColors.orange
                                                  .withValues(alpha: 0.15),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: MovieColors.orange
                                                    .withValues(alpha: 0.4),
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
                                              min: 0.60,
                                              max: 1.50,
                                              divisions: 18,
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
                                            label: '۶۰٪ بسیار فشرده',
                                            value: 0.60,
                                            current: access.uiScale,
                                            onSelect: access.setUiScale,
                                          ),
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
                                          _ScaleChip(
                                            label: '۱۵۰٪ بسیار بزرگ',
                                            value: 1.50,
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
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'اندازه متون و قلم‌ها',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13.5,
                                                  ),
                                                ),
                                                SizedBox(height: 2),
                                                Text(
                                                  'تغییر فقط اندازه متون و قلم‌های برنامه (بدون تغییر اندازه زیرنویس)',
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
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          _ScaleChip(
                                            label: '۸۵٪ فشرده',
                                            value: 0.85,
                                            current: access.textScale,
                                            onSelect: access.setTextScale,
                                          ),
                                          _ScaleChip(
                                            label: '۱۰۰٪ استاندارد',
                                            value: 1.00,
                                            current: access.textScale,
                                            onSelect: access.setTextScale,
                                          ),
                                          _ScaleChip(
                                            label: '۱۱۵٪ بزرگ',
                                            value: 1.15,
                                            current: access.textScale,
                                            onSelect: access.setTextScale,
                                          ),
                                          _ScaleChip(
                                            label: '۱۳۰٪ بسیار بزرگ',
                                            value: 1.30,
                                            current: access.textScale,
                                            onSelect: access.setTextScale,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 18),

                                      // Density
                                      DropdownButtonFormField<DensityMode>(
                                        value: access.densityMode,
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
                                          if (mode != null) {
                                            access.setDensity(mode);
                                          }
                                        },
                                      ),
                                      const SizedBox(height: 16),

                                      // Accessibility toggle cards
                                      _responsiveRow(
                                        first: _toggleCard(
                                          title:
                                              'کاهش انیمیشن‌ها (Reduce Motion)',
                                          subtitle:
                                              'ساده‌سازی ترنزیشن‌ها برای سرعت بالاتر',
                                          value: access.reduceMotion,
                                          onChanged: (val) =>
                                              access.setReduceMotion(val),
                                          icon: Icons.motion_photos_off_rounded,
                                        ),
                                        second: _toggleCard(
                                          title:
                                              'افزایش کنتراست (High Contrast)',
                                          subtitle:
                                              'پررنگ‌تر کردن مرزها و کارت‌ها جهت دید بهتر',
                                          value: access.highContrast,
                                          onChanged: (val) =>
                                              access.setHighContrast(val),
                                          icon: Icons.contrast_rounded,
                                        ),
                                      ),
                                      _responsiveRow(
                                        first: _toggleCard(
                                          title: 'نمایش متون پررنگ (Bold Text)',
                                          subtitle:
                                              'افزایش ضخامت نوشته‌ها برای سهولت در خواندن',
                                          value: access.boldText,
                                          onChanged: (val) =>
                                              access.setBoldText(val),
                                          icon: Icons.format_bold_rounded,
                                        ),
                                        second: _toggleCard(
                                          title:
                                              'بازخورد لرزشی کلیدها (Haptics)',
                                          subtitle:
                                              'لرزش خفیف هنگام لمس بخش‌های مختلف',
                                          value: access.haptics,
                                          onChanged: (val) =>
                                              access.setHaptics(val),
                                          icon: Icons.vibration_rounded,
                                        ),
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

                          // 5. همگام‌سازی ابری و عمومی
                          _section(
                            icon: Icons.cloud_sync_rounded,
                            title: 'همگام‌سازی و شخصی‌سازی',
                            subtitle:
                                'ذخیره‌سازی ابری روی سرور و تنظیمات عنوان‌ها',
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
                              const Divider(height: 20),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'نمایش عنوان‌های اصلی به انگلیسی',
                                ),
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
                        ],
                      ),
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
    String? subtitle,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 18),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
    color: MovieColors.surfaceHigh.withValues(alpha: 0.45),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: MovieColors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: MovieColors.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MovieColors.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          ...children,
        ],
      ),
    ),
  );

  Widget _responsiveRow({
    required Widget first,
    required Widget second,
    double breakpoint = 600,
  }) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= breakpoint) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 16),
            Expanded(child: second),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 12), second],
      );
    },
  );

  Widget _toggleCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    Color activeColor = MovieColors.orange,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: value
            ? activeColor.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.06),
      ),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (value ? activeColor : Colors.white).withValues(
              alpha: value ? 0.15 : 0.05,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: value ? activeColor : MovieColors.muted,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: MovieColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(value: value, activeColor: activeColor, onChanged: onChanged),
      ],
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
    Color activeColor = MovieColors.orange,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              suffix,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: activeColor,
              ),
            ),
          ),
        ],
      ),
      // Same global M3 slider as Accessibility (no custom thin theme).
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
              // Map bottomPadding (0..1000) linearly onto the preview height so
              // the full slider travel is visible, exactly like the player
              // (which uses the raw pixel offset from the video bottom).
              final travel = (constraints.maxHeight * .62).clamp(40.0, 220.0);
              const minBottom = 10.0;
              final fraction = (_subtitle.bottomPadding / 1000).clamp(0.0, 1.0);
              final bottom = minBottom + fraction * travel;
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _subtitle.backgroundColor.withValues(
                            alpha: _subtitle.backgroundOpacity,
                          ),
                          borderRadius: BorderRadius.circular(
                            _subtitle.cornerRadius,
                          ),
                        ),
                        child: Text(
                          'این یک پیش‌نمایش زیرنویس فارسی است\nتغییرات خط دوم هم‌زمان نمایش داده می‌شود',
                          key: const Key('subtitle-two-line-preview'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                            fontFamily: _subtitle.fontFamily,
                            fontSize: _subtitle.size,
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
