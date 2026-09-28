import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/platform_ui.dart';
import 'mbn_sync.dart';

enum DensityMode {
  compact('compact', 'فشرده (پیشنهادی برای موبایل)', VisualDensity.compact),
  standard('standard', 'استاندارد', VisualDensity.standard),
  comfortable('comfortable', 'جادار', VisualDensity.comfortable);

  const DensityMode(this.key, this.label, this.density);
  final String key;
  final String label;
  final VisualDensity density;

  static DensityMode fromKey(String? key) {
    final isPhone = Platform.isAndroid && !isAndroidTv;
    return DensityMode.values.firstWhere(
      (m) => m.key == key,
      orElse: () => isPhone ? DensityMode.compact : DensityMode.standard,
    );
  }
}

/// سرویس مدیریت دسترسی‌پذیری و مقیاس نمای صفحه
/// همگام‌سازی ابری این تنظیمات به‌صورت کاملاً مجزا برای گوشی و کامپیوتر در سرور ذخیره می‌شود.
class AccessibilityService extends ChangeNotifier {
  AccessibilityService._();
  static final AccessibilityService instance = AccessibilityService._();

  static const String keyUiScale = 'access_ui_scale';
  static const String keyTextScale = 'access_text_scale';
  static const String keyDensity = 'access_density';
  static const String keyReduceMotion = 'access_reduce_motion';
  static const String keyHighContrast = 'access_high_contrast';
  static const String keyBoldText = 'access_bold_text';
  static const String keyHaptics = 'access_haptic_feedback';
  static const String keyLargeSubtitles = 'access_large_subtitles';

  static bool get isPhoneDevice => Platform.isAndroid && !isAndroidTv;

  double _uiScale = 1.0;
  double _textScale = 1.0;
  DensityMode _densityMode = DensityMode.standard;
  bool _reduceMotion = false;
  bool _highContrast = false;
  bool _boldText = false;
  bool _haptics = true;
  bool _largeSubtitles = false;
  bool _initialized = false;

  double get uiScale => _uiScale;
  double get textScale => _textScale;
  DensityMode get densityMode => _densityMode;
  VisualDensity get visualDensity => _densityMode.density;
  bool get reduceMotion => _reduceMotion;
  bool get highContrast => _highContrast;
  bool get boldText => _boldText;
  bool get haptics => _haptics;
  bool get largeSubtitles => _largeSubtitles;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _readFromPrefs(prefs);
  }

  void _readFromPrefs(SharedPreferences prefs) {
    // روی گوشی همراه به‌صورت پیش‌فرض مقیاس فشرده‌تر (0.85) اعمال می‌شود
    final defaultScale = isPhoneDevice ? 0.85 : 1.0;
    _uiScale = (prefs.getDouble(keyUiScale) ?? defaultScale).clamp(0.70, 1.30);
    _textScale = (prefs.getDouble(keyTextScale) ?? 1.0).clamp(0.80, 1.40);
    _densityMode = DensityMode.fromKey(prefs.getString(keyDensity));
    _reduceMotion = prefs.getBool(keyReduceMotion) ?? false;
    _highContrast = prefs.getBool(keyHighContrast) ?? false;
    _boldText = prefs.getBool(keyBoldText) ?? false;
    _haptics = prefs.getBool(keyHaptics) ?? true;
    _largeSubtitles = prefs.getBool(keyLargeSubtitles) ?? false;
  }

  Future<void> reloadFromStore() async {
    final prefs = await SharedPreferences.getInstance();
    _readFromPrefs(prefs);
    notifyListeners();
  }

  Future<void> setUiScale(double scale) async {
    final clamped = (scale * 100).round() / 100.0;
    final value = clamped.clamp(0.70, 1.30);
    if ((_uiScale - value).abs() < 0.005) return;
    _uiScale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keyUiScale, value);
    hapticFeedback();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> setTextScale(double scale) async {
    final clamped = (scale * 100).round() / 100.0;
    final value = clamped.clamp(0.80, 1.40);
    if ((_textScale - value).abs() < 0.005) return;
    _textScale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keyTextScale, value);
    hapticFeedback();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> setDensity(DensityMode mode) async {
    if (_densityMode == mode) return;
    _densityMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyDensity, mode.key);
    hapticFeedback();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> setReduceMotion(bool value) async {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyReduceMotion, value);
    hapticFeedback();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> setHighContrast(bool value) async {
    if (_highContrast == value) return;
    _highContrast = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyHighContrast, value);
    hapticFeedback();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> setBoldText(bool value) async {
    if (_boldText == value) return;
    _boldText = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyBoldText, value);
    hapticFeedback();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> setHaptics(bool value) async {
    if (_haptics == value) return;
    _haptics = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyHaptics, value);
    if (value) HapticFeedback.lightImpact();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> setLargeSubtitles(bool value) async {
    if (_largeSubtitles == value) return;
    _largeSubtitles = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyLargeSubtitles, value);
    hapticFeedback();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  Future<void> resetToDefaults() async {
    final defaultScale = isPhoneDevice ? 0.85 : 1.0;
    _uiScale = defaultScale;
    _textScale = 1.0;
    _densityMode = isPhoneDevice ? DensityMode.compact : DensityMode.standard;
    _reduceMotion = false;
    _highContrast = false;
    _boldText = false;
    _haptics = true;
    _largeSubtitles = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyUiScale);
    await prefs.remove(keyTextScale);
    await prefs.remove(keyDensity);
    await prefs.remove(keyReduceMotion);
    await prefs.remove(keyHighContrast);
    await prefs.remove(keyBoldText);
    await prefs.remove(keyHaptics);
    await prefs.remove(keyLargeSubtitles);
    hapticFeedback();
    unawaited(MbnSync.instance.pushPreferencesThrottled());
  }

  void hapticFeedback() {
    if (_haptics) {
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }
  }
}
