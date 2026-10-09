import 'app_platform.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mbn_sync.dart';

class SubtitlePreferences {
  const SubtitlePreferences({
    this.originalAss = false,
    this.fontFamily = 'Vazirmatn',
    this.size = 14,
    this.lineHeight = 1.45,
    this.backgroundColor = Colors.black,
    this.backgroundOpacity = .62,
    this.cornerRadius = 10,
    this.bottomPadding = 54,
    this.color = Colors.white,
    this.bold = true,
    this.shadow = true,
    this.delay = 0,
    this.timingScale = 1,
  });

  /// First-run default subtitle size: 14 on phones, 24 on Windows.
  /// Server just mirrors whatever the app pushes per platform
  /// (windows/android buckets), so fixing the app default is enough.
  static double get platformDefaultSize => Platform.isWindows ? 24.0 : 14.0;

  /// Non-const constructor for first-run / reset values.
  factory SubtitlePreferences.withPlatformDefaults() =>
      SubtitlePreferences(size: platformDefaultSize);

  final bool originalAss;
  final String fontFamily;
  final double size;
  final double lineHeight;
  final Color backgroundColor;
  final double backgroundOpacity;
  final double cornerRadius;
  final double bottomPadding;
  final Color color;
  final bool bold;
  final bool shadow;
  final double delay;
  final double timingScale;

  SubtitlePreferences copyWith({
    bool? originalAss,
    String? fontFamily,
    double? size,
    double? lineHeight,
    Color? backgroundColor,
    double? backgroundOpacity,
    double? cornerRadius,
    double? bottomPadding,
    Color? color,
    bool? bold,
    bool? shadow,
    double? delay,
    double? timingScale,
  }) => SubtitlePreferences(
    originalAss: originalAss ?? this.originalAss,
    fontFamily: fontFamily ?? this.fontFamily,
    size: size ?? this.size,
    lineHeight: lineHeight ?? this.lineHeight,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    bottomPadding: bottomPadding ?? this.bottomPadding,
    color: color ?? this.color,
    bold: bold ?? this.bold,
    shadow: shadow ?? this.shadow,
    delay: delay ?? this.delay,
    timingScale: timingScale ?? this.timingScale,
  );

  factory SubtitlePreferences.fromStore(SharedPreferences prefs) =>
      SubtitlePreferences(
        originalAss: prefs.getBool('sub_original_ass') ?? false,
        fontFamily: prefs.getString('sub_font') ?? 'Vazirmatn',
        size: prefs.getDouble('sub_size') ?? platformDefaultSize,
        lineHeight: prefs.getDouble('sub_height') ?? 1.45,
        backgroundColor: Color(
          prefs.getInt('sub_bg_color') ?? Colors.black.toARGB32(),
        ),
        backgroundOpacity: prefs.getDouble('sub_bg') ?? .62,
        cornerRadius: prefs.getDouble('sub_radius') ?? 10,
        bottomPadding: prefs.getDouble('sub_bottom') ?? 54,
        color: Color(prefs.getInt('sub_color') ?? Colors.white.toARGB32()),
        bold: prefs.getBool('sub_bold') ?? true,
        shadow: prefs.getBool('sub_shadow') ?? true,
        delay: prefs.getDouble('sub_delay') ?? 0,
        timingScale: prefs.getDouble('sub_timing_scale') ?? 1,
      );

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setBool('sub_original_ass', originalAss);
    await prefs.setString('sub_font', fontFamily);
    await prefs.setDouble('sub_size', size);
    await prefs.setDouble('sub_height', lineHeight);
    await prefs.setInt('sub_bg_color', backgroundColor.toARGB32());
    await prefs.setDouble('sub_bg', backgroundOpacity);
    await prefs.setDouble('sub_radius', cornerRadius);
    await prefs.setDouble('sub_bottom', bottomPadding);
    await prefs.setInt('sub_color', color.toARGB32());
    await prefs.setBool('sub_bold', bold);
    await prefs.setBool('sub_shadow', shadow);
    await prefs.setDouble('sub_delay', delay);
    await prefs.setDouble('sub_timing_scale', timingScale);
    await MbnSync.instance.pushPreferences();
  }
}

abstract final class PlaybackPreferenceStore {
  static const askEveryTime = 'ask';
  static const internalPlayer = 'internal';
  static const miracast = 'miracast';

  // Latency belongs to this audio output/device, not account-wide settings.
  static const audioDelayKey = 'device_audio_delay_seconds';

  static Future<double> audioDelay() async =>
      ((await SharedPreferences.getInstance()).getDouble(audioDelayKey) ?? 0)
          .clamp(-3.0, 3.0);

  static Future<void> setAudioDelay(double seconds) async {
    await (await SharedPreferences.getInstance()).setDouble(
      audioDelayKey,
      seconds.clamp(-3.0, 3.0),
    );
  }

  static const defaultPlayerKey = 'default_video_player';
  static const defaultStreamerKey = 'default_streamer';

  static Future<String> defaultPlayer() async =>
      (await SharedPreferences.getInstance()).getString(defaultPlayerKey) ??
      askEveryTime;

  static Future<String> defaultStreamer() async =>
      (await SharedPreferences.getInstance()).getString(defaultStreamerKey) ??
      askEveryTime;

  static Future<void> setDefaultPlayer(String value) async {
    await (await SharedPreferences.getInstance()).setString(
      defaultPlayerKey,
      value,
    );
    await MbnSync.instance.pushPreferences();
  }

  static Future<void> setDefaultStreamer(String value) async {
    await (await SharedPreferences.getInstance()).setString(
      defaultStreamerKey,
      value,
    );
    await MbnSync.instance.pushPreferences();
  }

  static Future<bool> recordPlayerUse(String value) =>
      _recordUse(group: 'player', value: value, suggestAt: 4);

  static Future<bool> recordStreamerUse(String value) =>
      _recordUse(group: 'streamer', value: value, suggestAt: 3);

  static Future<bool> _recordUse({
    required String group,
    required String value,
    required int suggestAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final defaultKey = group == 'player'
        ? defaultPlayerKey
        : defaultStreamerKey;
    if ((prefs.getString(defaultKey) ?? askEveryTime) != askEveryTime) {
      return false;
    }
    final countKey = '${group}_use_$value';
    final promptedKey = '${group}_suggested_$value';
    final count = (prefs.getInt(countKey) ?? 0) + 1;
    await prefs.setInt(countKey, count);
    if (count < suggestAt || (prefs.getBool(promptedKey) ?? false)) {
      return false;
    }
    await prefs.setBool(promptedKey, true);
    return true;
  }
}
