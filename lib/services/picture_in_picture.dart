import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Small Android platform bridge for the system Picture-in-Picture window.
///
/// Keeping this bridge in the app (instead of adding a PiP plugin) lets the
/// player use Android's current APIs while preserving the existing media_kit
/// surface and Flutter subtitle overlay.
class PictureInPictureController extends ValueNotifier<bool> {
  PictureInPictureController() : _isAndroid = Platform.isAndroid, super(false);

  static const MethodChannel _channel = MethodChannel('com.mbn.movie/pip');

  final bool _isAndroid;
  bool _supported = false;

  bool get supported => _supported;

  Future<bool> initialize() async {
    if (!_isAndroid) return false;
    _channel.setMethodCallHandler(_handlePlatformCall);
    try {
      _supported = await _channel.invokeMethod<bool>('isSupported') ?? false;
      value = await _channel.invokeMethod<bool>('isInPipMode') ?? false;
    } on PlatformException {
      _supported = false;
      value = false;
    }
    return _supported;
  }

  Future<void> configure({
    required bool autoEnter,
    required double aspectRatio,
    required String title,
    required String subtitle,
  }) async {
    if (!_isAndroid || !_supported) return;
    try {
      await _channel.invokeMethod<void>('configure', {
        'autoEnter': autoEnter,
        'aspectRatio': aspectRatio,
        'title': title,
        'subtitle': subtitle,
      });
    } on PlatformException {
      // PiP availability may change through device policy while the app runs.
    }
  }

  Future<bool> enter({
    required double aspectRatio,
    required String title,
    required String subtitle,
  }) async {
    if (!_isAndroid || !_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('enter', {
            'aspectRatio': aspectRatio,
            'title': title,
            'subtitle': subtitle,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> deactivate() async {
    if (!_isAndroid || !_supported) return;
    try {
      await _channel.invokeMethod<void>('deactivate');
    } on PlatformException {
      // The activity may already be detaching during navigation.
    }
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'onPipTransitionStarted':
        value = true;
        return;
      case 'onPipModeChanged':
        value = call.arguments == true;
        return;
    }
  }

  @override
  void dispose() {
    if (_isAndroid) _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
