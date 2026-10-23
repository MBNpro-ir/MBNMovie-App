/// This file is a part of media_kit (https://github.com/media-kit/media-kit).
///
/// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
/// All rights reserved.
/// Use of this source code is governed by MIT license that can be found in the LICENSE file.
import '../bounded_video_output.dart';
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'package:media_kit/media_kit.dart';

import 'package:media_kit_video/src/utils/query_decoders.dart';
import 'package:media_kit_video/src/video_controller/platform_video_controller.dart';

/// {@template android_video_controller}
///
/// AndroidVideoController
/// ----------------------
///
/// The [PlatformVideoController] implementation based on native JNI & C/C++ used on Android.
///
/// {@endtemplate}
class AndroidVideoController extends PlatformVideoController {
  /// Whether [AndroidVideoController] is supported on the current platform or not.
  static bool get supported => Platform.isAndroid;

  /// Pointer address to the global object reference of `android.view.Surface` i.e. `(intptr_t)(*android.view.Surface)`.
  final ValueNotifier<int?> wid = ValueNotifier<int?>(null);

  /// [Lock] used to synchronize [onLoadHooks], [onUnloadHooks] & [subscription].
  final lock = Lock();
  final _surfaceReady = Completer<void>();
  bool _nativeSubtitles = false;
  bool _gpuFallback = false;
  bool _disposing = false;
  Future<bool>? _recovering;
  bool get _directConfigured => configuration.vo == 'mediacodec_embed';
  String get _output => _directConfigured && (_nativeSubtitles || _gpuFallback)
      ? 'gpu'
      : configuration.vo!;

  NativePlayer get platform => player.platform as NativePlayer;

  Future<void> setProperty(String key, String value) async {
    if (_disposing || platform.disposed) return;
    await platform.setProperty(key, value, waitForInitialization: false);
  }

  Future<void> setProperties(Map<String, String> properties) async {
    for (final entry in properties.entries) {
      await setProperty(entry.key, entry.value);
    }
  }

  /// Listener for updating the --wid property.
  Future<void> widListener() => lock.synchronized(_updateSurface);

  Future<void> _updateSurface() async {
    if (_disposing) return;
    final width = rect.value?.width.toInt() ?? 1;
    final height = rect.value?.height.toInt() ?? 1;
    final androidSurfaceSizeValue = [width, height].join('x');
    final widValue = wid.value?.toString() ?? '0';
    // When --wid is 0, vo=null is required to avoid SIGSEGV.
    final voValue = widValue == '0' ? 'null' : _output;
    final vidValue = widValue == '0' ? 'no' : 'auto';
    // It is important to re-initialize --vo after --android-surface-size.
    if (_directConfigured) await setProperty('vid', 'no');
    await setProperty('vo', 'null');
    await setProperties(
      {
        // ORDER IS IMPORTANT.
        'android-surface-size': androidSurfaceSizeValue,
        'wid': widValue,
        if (_directConfigured)
          'hwdec': voValue == 'mediacodec_embed'
              ? configuration.hwdec!
              : 'auto-safe',
        'vo': voValue,
        // It is important to re-initialize --vid in-case of --vo=mediacodec_embed.
        // Not doing so causes error "Could not open codec." & video never gets rendered.
        if (_directConfigured) 'vid': vidValue,
      },
    );
    // Instead of seeking to the start (Duration.zero), seek to the current playback position
    // without jumping the user to the start of the media.
    if (widValue != '0' && !_surfaceReady.isCompleted) {
      _surfaceReady.complete();
    }
    if (!_disposing &&
        !platform.disposed &&
        player.state.playlist.medias.isNotEmpty &&
        await platform.getProperty('idle-active') != 'yes') {
      final currentPosition = player.state.position;
      await player.seek(currentPosition);
    }
  }

  @override
  Future<void> setNativeSubtitleRendering(bool enabled,
      {bool resetDecoder = false}) {
    if (!_directConfigured) return Future.value();
    return lock.synchronized(() async {
      final before = _output;
      _nativeSubtitles = enabled;
      if (resetDecoder) _gpuFallback = false;
      if (before != _output) await _updateSurface();
    });
  }

  @override
  Future<void> waitForVideoOutputRecovery() async {
    final pending = _recovering;
    if (pending != null) await pending;
  }

  @override
  Future<bool> recoverVideoOutput(String error) {
    if (_recovering != null) return _recovering!;
    if (_disposing ||
        !_directConfigured ||
        _output != 'mediacodec_embed' ||
        !(error.contains('Could not open codec') ||
            error.contains('video conversion') ||
            error.contains('HW uploader'))) {
      return Future.value(false);
    }
    _gpuFallback = true;
    late final Future<bool> work;
    work = lock.synchronized(() async {
      try {
        final playlist = player.state.playlist;
        final media =
            playlist.index >= 0 && playlist.index < playlist.medias.length
                ? playlist.medias[playlist.index]
                : null;
        final position = player.state.position;
        final play = await platform.getProperty('pause') != 'yes';
        await _updateSurface();
        // A fatal format conversion can unload the video before Dart receives
        // the log. Re-open that same media after changing outputs, preserving
        // the pause state and checkpoint instead of leaving an idle player.
        if (!_disposing &&
            !platform.disposed &&
            await platform.getProperty('idle-active') == 'yes') {
          if (media == null) return false;
          await player.open(media, play: play);
          if (position > Duration.zero) await player.seek(position);
        }
        return true;
      } catch (_) {
        return false;
      }
    }).whenComplete(() {
      if (identical(_recovering, work)) _recovering = null;
    });
    _recovering = work;
    return work;
  }

  /// [StreamSubscription] for listening to video [Rect].
  StreamSubscription<VideoParams>? videoParamsSubscription;
  StreamSubscription<PlayerLog>? logSubscription;

  /// {@macro android_video_controller}
  AndroidVideoController._(
    super.player,
    super.configuration,
  ) {
    wid.addListener(widListener);
    // media_kit's error stream omits autoconvert errors and fatal vf messages.
    // Those are the failure mode of a software-only codec with direct output.
    logSubscription = player.stream.log.listen((log) {
      if (log.level == 'error' || log.level == 'fatal') {
        unawaited(recoverVideoOutput(log.text));
      }
    });
    videoParamsSubscription = player.stream.videoParams.listen(
      (event) => lock.synchronized(() async {
        if (_disposing || platform.disposed) return;
        int width;
        int height;
        if (event.rotate == 0 || event.rotate == 180) {
          width = event.dw ?? 0;
          height = event.dh ?? 0;
        } else {
          // width & height are swapped for 90 or 270 degrees rotation.
          width = event.dh ?? 0;
          height = event.dw ?? 0;
        }

        final bounded = boundedVideoOutput(
          width,
          height,
          maxWidth: configuration.width,
          maxHeight: configuration.height,
        );
        width = bounded.width;
        height = bounded.height;

        final isZero = width == 0 || height == 0;
        final isSame = width == rect.value?.width.toInt() &&
            height == rect.value?.height.toInt();
        if (isZero || isSame) {
          return;
        }

        final handle = await player.handle;
        if (_disposing || platform.disposed) return;

        await _channel.invokeMethod(
          'VideoOutputManager.SetSurfaceSize',
          {
            'handle': handle.toString(),
            'width': width.toString(),
            'height': height.toString(),
          },
        );

        if (_disposing || platform.disposed) return;
        rect.value = Rect.fromLTWH(
          0.0,
          0.0,
          width.toDouble(),
          height.toDouble(),
        );

        if (!waitUntilFirstFrameRenderedCompleter.isCompleted) {
          waitUntilFirstFrameRenderedCompleter.complete();
        }
      }),
    );
  }

  /// {@macro android_video_controller}
  static Future<PlatformVideoController> create(
    Player player,
    VideoControllerConfiguration configuration,
  ) async {
    Future<String> getDefaultHwdec() async {
      // Enforce software rendering in emulators.
      bool hw = configuration.enableHardwareAcceleration;
      final bool isEmulator = await _channel.invokeMethod('Utils.IsEmulator');
      if (isEmulator) {
        hw = false;
        debugPrint('media_kit: Emulator detected.');
        debugPrint('media_kit: Enforcing S/W rendering.');
      }
      return hw ? 'auto-safe' : 'no';
    }

    // Update [configuration] to have default values.
    configuration = configuration.copyWith(
      vo: configuration.vo ?? 'gpu',
      hwdec: configuration.hwdec ?? await getDefaultHwdec(),
    );

    // Retrieve the native handle of the [Player].
    final handle = await player.handle;
    // Return the existing [VideoController] if it's already created.
    if (_controllers.containsKey(handle)) {
      return _controllers[handle]!;
    }

    // In case no video-decoders are found, this means media_kit_libs_***_audio is being used.
    // Thus, --vid=no is required to prevent libmpv from trying to decode video (otherwise bad things may happen).
    //
    // Search for common H264 decoder to check if video support is available.
    final decoders = await queryDecoders(handle);
    if (!decoders.contains('h264')) {
      throw UnsupportedError(
        '[VideoController] is not available.'
        ' '
        'Please use media_kit_libs_***_video instead of media_kit_libs_***_audio.',
      );
    }

    // Creation:
    final controller = AndroidVideoController._(
      player,
      configuration,
    );

    // Register [_dispose] for execution upon [Player.dispose].
    player.platform?.release.add(controller._dispose);

    // Store the [VideoController] in the [_controllers].
    _controllers[handle] = controller;

    await _channel.invokeMethod(
      'VideoOutputManager.Create',
      {
        'handle': handle.toString(),
      },
    );

    await controller.setProperties(
      {
        // It is necessary to set vo=null here to avoid SIGSEGV, --wid must be assigned before vo=gpu is set.
        'vo': 'null',
        'hwdec': configuration.hwdec!,
        'vid': 'auto',
        'opengl-es': 'yes',
        'force-window': 'yes',
        'gpu-context': 'android',
        'sub-use-margins': 'no',
        'sub-font-provider': 'none',
        'sub-scale-with-window': 'yes',
        'hwdec-codecs': 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1',
      },
    );

    // Direct MediaCodec needs a Surface before the decoder can emit video
    // parameters. GPU output can wait until the source dimensions are known.
    if (!(configuration.androidAttachSurfaceAfterVideoParameters ??
        configuration.vo == 'gpu')) {
      await _channel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
        'handle': handle.toString(),
        'width': (configuration.width ?? 1).toString(),
        'height': (configuration.height ?? 1).toString(),
      });
      await controller._surfaceReady.future;
    }

    // Return the [PlatformVideoController].
    return controller;
  }

  /// Sets the required size of the video output.
  /// This may yield substantial performance improvements if a small [width] & [height] is specified.
  ///
  /// Remember:
  /// * “Premature optimization is the root of all evil”
  /// * “With great power comes great responsibility”
  @override
  Future<void> setSize({
    int? width,
    int? height,
  }) {
    throw UnsupportedError(
      '[AndroidVideoController.setSize] is not available on Android',
    );
  }

  /// Disposes the instance. Releases allocated resources back to the system.
  Future<void> _dispose() async {
    _disposing = true;
    wid.removeListener(widListener);
    await videoParamsSubscription?.cancel();
    await logSubscription?.cancel();
    wid.dispose();
    super.dispose();
    final handle = await player.handle;
    _controllers.remove(handle);
    await _channel.invokeMethod(
      'VideoOutputManager.Dispose',
      {
        'handle': handle.toString(),
      },
    );
  }

  /// Currently created [AndroidVideoController]s.
  static final _controllers = HashMap<int, AndroidVideoController>();

  /// [MethodChannel] for invoking platform specific native implementation.
  static final _channel =
      const MethodChannel('com.alexmercerind/media_kit_video')
        ..setMethodCallHandler(
          (MethodCall call) async {
            try {
              debugPrint(call.method.toString());
              debugPrint(call.arguments.toString());
              switch (call.method) {
                case 'VideoOutput.Resize':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    final Rect rect = Rect.fromLTWH(
                      call.arguments['rect']['left'] * 1.0,
                      call.arguments['rect']['top'] * 1.0,
                      call.arguments['rect']['width'] * 1.0,
                      call.arguments['rect']['height'] * 1.0,
                    );
                    final int id = call.arguments['id'];
                    final int wid = call.arguments['wid'];
                    _controllers[handle]?.rect.value = rect;
                    _controllers[handle]?.id.value = id;
                    _controllers[handle]?.wid.value = wid;
                    break;
                  }
                case 'VideoOutput.WaitUntilFirstFrameRenderedNotify':
                  {
                    // Notify about updated texture ID & [Rect].
                    final int handle = call.arguments['handle'];
                    debugPrint(handle.toString());
                    // Notify about the first frame being rendered.
                    final completer = _controllers[handle]
                        ?.waitUntilFirstFrameRenderedCompleter;
                    if (!(completer?.isCompleted ?? true)) {
                      completer?.complete();
                    }
                    break;
                  }
                default:
                  {
                    break;
                  }
              }
            } catch (exception, stacktrace) {
              debugPrint(exception.toString());
              debugPrint(stacktrace.toString());
            }
          },
        );
}
