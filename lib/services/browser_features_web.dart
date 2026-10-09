import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

abstract final class BrowserFeatures {
  static bool get isAndroidBrowser =>
      web.window.navigator.userAgent.toLowerCase().contains('android');
  static bool openExternal(Uri uri) {
    // Call before any await in the button's handler to retain Safari's gesture.
    web.window.location.assign(uri.toString());
    return true;
  }

  static double _audioDelay = 0;
  static void setAudioDelay(double value) {
    _audioDelay = value.clamp(-3.0, 3.0);
    final video = _audioVideo;
    if (video != null && _audio != null) {
      _audio!.currentTime = _audioTarget(video);
    }
  }

  static double _audioTarget(web.HTMLVideoElement video) =>
      (video.currentTime - _audioDelay * video.playbackRate).clamp(
        0.0,
        double.infinity,
      );

  static void setPlayerActive(bool active) =>
      globalContext.setProperty('mbnPlayerActive'.toJS, active.toJS);

  static web.HTMLDivElement? _safeAreaProbe;
  static ({double left, double top, double right, double bottom}) get safeArea {
    final probe = _safeAreaProbe ??= web.HTMLDivElement()
      ..style.cssText =
          'position:fixed;visibility:hidden;pointer-events:none;'
          'padding:env(safe-area-inset-top) env(safe-area-inset-right) '
          'env(safe-area-inset-bottom) env(safe-area-inset-left);';
    if (!probe.isConnected) web.document.body!.appendChild(probe);
    final style = web.window.getComputedStyle(probe);
    double px(String value) => double.tryParse(value.replaceAll('px', '')) ?? 0;
    return (
      left: px(style.paddingLeft),
      top: px(style.paddingTop),
      right: px(style.paddingRight),
      bottom: px(style.paddingBottom),
    );
  }

  static bool get isMobileBrowser {
    final nav = web.window.navigator;
    final ua = nav.userAgent.toLowerCase();
    return RegExp(r'android|iphone|ipad|ipod|mobile').hasMatch(ua) ||
        (ua.contains('macintosh') && nav.maxTouchPoints > 1);
  }

  static bool get isAppleMobile =>
      RegExp(
        r'iphone|ipad|ipod',
        caseSensitive: false,
      ).hasMatch(web.window.navigator.userAgent) ||
      (web.window.navigator.vendor.contains('Apple') &&
          web.window.navigator.maxTouchPoints > 1);

  // Invoke play before the first await, while a real tap still owns the
  // Safari user gesture. Network preparation cannot retain that permission.
  static Future<bool> play({int? handle, bool Function()? active}) async {
    var video = _video;
    if (video == null && handle != null) {
      final instances = globalContext.getProperty<JSObject?>(
        r'$com.alexmercerind.media_kit.instances'.toJS,
      );
      video = instances?.getProperty<web.HTMLVideoElement>(
        handle.toString().toJS,
      );
    }
    if (video == null) throw StateError('Video is not attached');
    try {
      await video.play().toDart;
      return true;
    } catch (error) {
      if ((error as web.DOMException).name == 'NotAllowedError') {
        if (active?.call() == false) return false;
        _showTapToPlay(video);
        return false;
      }
      rethrow;
    }
  }

  static void clearPlayPrompt() => _clearTapToPlay();
  static web.HTMLButtonElement? _tapButton;
  static web.HTMLVideoElement? _tapVideo;
  static JSFunction? _tapPlaying;
  static void _clearTapToPlay() {
    if (_tapPlaying != null) {
      _tapVideo?.removeEventListener('playing', _tapPlaying);
    }
    _tapPlaying = null;
    _tapVideo = null;
    _tapButton?.remove();
    _tapButton = null;
  }

  static void _showTapToPlay(web.HTMLVideoElement video) {
    _clearTapToPlay();
    final button = web.HTMLButtonElement()
      ..textContent = 'برای شروع پخش لمس کن'
      ..setAttribute('aria-label', 'برای شروع پخش لمس کن');
    button.style
      ..position = 'fixed'
      ..left = '50%'
      ..top = '50%'
      ..transform = 'translate(-50%, -50%)'
      ..zIndex = '10000'
      ..padding = '16px 22px'
      ..border = '1px solid white'
      ..borderRadius = '16px'
      ..backgroundColor = '#202535'
      ..color = 'white'
      ..font = 'bold 16px Tahoma, sans-serif'
      ..cursor = 'pointer';
    // A native click calls play synchronously, before Flutter's gesture
    // recognizers or an async lock can consume Safari's transient permission.
    button.addEventListener(
      'click',
      ((web.Event _) {
        video
            .play()
            .toDart
            .then((_) {
              if (_tapButton == button) _clearTapToPlay();
            })
            .catchError((Object _) {
              button.textContent = 'پخش انجام نشد؛ دوباره لمس کن';
            });
      }).toJS,
    );
    _tapVideo = video;
    _tapPlaying = ((web.Event _) {
      if (_tapButton == button) _clearTapToPlay();
    }).toJS;
    video.addEventListener(
      'playing',
      _tapPlaying,
      web.AddEventListenerOptions(once: true),
    );
    _tapButton = button;
    web.document.body!.appendChild(button);
  }

  static bool get castSupported =>
      _video != null &&
      (_video!.hasProperty('webkitShowPlaybackTargetPicker'.toJS).toDart ||
          _video!.getProperty<JSObject?>('remote'.toJS) != null);

  static bool get requiresCompatibleVideo =>
      web.window.navigator.vendor.contains('Apple');
  static web.HTMLVideoElement? _ownedVideo;
  static void attachVideo(web.HTMLVideoElement video) {
    _ownedVideo = video;
    if (_pendingSubtitle != null) _installSubtitle(_pendingSubtitle!);
  }

  static void detachVideo(web.HTMLVideoElement video) {
    if (_ownedVideo == video) {
      _clearTapToPlay();
      _ownedVideo = null;
    }
  }

  static web.HTMLVideoElement? get _video =>
      _ownedVideo ??
      web.document.querySelector('video') as web.HTMLVideoElement?;
  static void download(String url, String name) {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..target = '_blank'
      ..rel = 'noopener';
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
  }

  static void saveBytes(Uint8List bytes, String name, String mime) {
    final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
    final url = web.URL.createObjectURL(blob);
    download(url, name);
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }

  static int _fullscreenGeneration = 0;
  static bool _fullscreenWanted = false;
  static web.HTMLVideoElement? _fullscreenVideo;

  // A requestFullscreen promise can settle after the player has closed.
  // Check ownership after every await so that exit always wins that race.
  static Future<bool> fullscreen(bool value) async {
    final generation = ++_fullscreenGeneration;
    _fullscreenWanted = value;
    if (!value) return _exitFullscreen();
    bool current() => generation == _fullscreenGeneration;
    try {
      if (web.document.fullscreenElement != null) return true;
      if (web.document.fullscreenEnabled) {
        await web.document.documentElement!.requestFullscreen().toDart;
        if (!current()) {
          if (!_fullscreenWanted) await _exitFullscreen();
          return false;
        }
        try {
          await web.window.screen.orientation
              .callMethod<JSPromise<JSAny?>>('lock'.toJS, 'landscape'.toJS)
              .toDart;
        } catch (_) {}
        if (!current()) {
          if (!_fullscreenWanted) await _exitFullscreen();
          return false;
        }
        return true;
      }
      final video = _video;
      if (video != null &&
          video.hasProperty('webkitEnterFullscreen'.toJS).toDart) {
        _fullscreenVideo = video;
        if (_track != null) _track!.track.mode = 'showing';
        video.addEventListener(
          'webkitendfullscreen',
          ((web.Event e) {
            if (_track != null) _track!.track.mode = 'hidden';
          }).toJS,
          web.AddEventListenerOptions(once: true),
        );
        video.callMethod<JSAny?>('webkitEnterFullscreen'.toJS);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> _exitFullscreen() async {
    final video = _fullscreenVideo ?? _video;
    _fullscreenVideo = null;
    try {
      if (video != null &&
          video.hasProperty('webkitDisplayingFullscreen'.toJS).toDart &&
          video
                  .getProperty<JSBoolean?>('webkitDisplayingFullscreen'.toJS)
                  ?.toDart ==
              true) {
        video.callMethod<JSAny?>('webkitExitFullscreen'.toJS);
      }
    } catch (_) {}
    try {
      if (web.document.fullscreenElement != null) {
        await web.document.exitFullscreen().toDart;
      }
    } catch (_) {}
    try {
      web.window.screen.orientation.callMethod<JSAny?>('unlock'.toJS);
    } catch (_) {}
    return false;
  }

  static bool get pipSupported =>
      web.document.pictureInPictureEnabled ||
      (_video?.hasProperty('webkitSetPresentationMode'.toJS).toDart ?? false);
  static Future<bool> pip() async {
    try {
      final video = _video;
      if (video == null) return false;
      if (web.document.pictureInPictureEnabled) {
        await video.requestPictureInPicture().toDart;
      } else {
        video.callMethod<JSAny?>(
          'webkitSetPresentationMode'.toJS,
          'picture-in-picture'.toJS,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> cast() async {
    try {
      final video = _video;
      if (video == null) return false;
      if (video.hasProperty('webkitShowPlaybackTargetPicker'.toJS).toDart) {
        video.callMethod<JSAny?>('webkitShowPlaybackTargetPicker'.toJS);
        return true;
      }
      final remote = video.getProperty<JSObject?>('remote'.toJS);
      if (remote != null) {
        await remote.callMethod<JSPromise<JSAny?>>('prompt'.toJS).toDart;
        return true;
      }
    } catch (_) {}
    return false;
  }

  static void stop() {
    _clearTapToPlay();
    clearAudio();
    clearSubtitle();
    final video = _video;
    if (video != null) {
      video.pause();
      video.removeAttribute('src');
      video.load();
    }
    unawaited(fullscreen(false));
  }

  static void muteOriginal(bool value) {
    if (_video != null) _video!.muted = value;
  }

  static web.HTMLButtonElement? _audioTapButton;
  static Completer<void>? _audioTapPending;
  static web.HTMLAudioElement? _audio;
  static web.HTMLVideoElement? _audioVideo;
  static JSFunction? _audioSync;
  static const _audioEvents = [
    'play',
    'pause',
    'seeked',
    'ratechange',
    'timeupdate',
    'volumechange',
    'waiting',
    'playing',
    'ended',
  ];
  static void clearAudio() {
    _audioTapButton?.remove();
    _audioTapButton = null;
    _audioTapPending?.complete();
    _audioTapPending = null;
    if (_audioSync != null && _audioVideo != null) {
      for (final event in _audioEvents) {
        _audioVideo!.removeEventListener(event, _audioSync);
      }
    }
    _audioSync = null;
    _audioVideo = null;
    _audio?.pause();
    _audio?.remove();
    _audio = null;
    if (_video != null) _video!.muted = false;
  }

  static Future<void> externalAudio(String url, {double delay = 0}) async {
    _audioDelay = delay.clamp(-3.0, 3.0);
    clearAudio();
    final video = _video;
    if (video == null) throw StateError('No video');
    final audio = web.HTMLAudioElement()
      ..src = url
      ..preload = 'auto';
    _audio = audio;
    web.document.body!.appendChild(audio);
    audio.currentTime = _audioTarget(video);
    audio.playbackRate = video.playbackRate;
    audio.volume = video.volume;
    try {
      if (!video.paused) await audio.play().toDart;
    } catch (error) {
      if (_audio != audio) return;
      if ((error as web.DOMException).name != 'NotAllowedError') {
        if (_audio == audio) clearAudio();
        rethrow;
      }
      final permission = Completer<void>();
      _audioTapPending = permission;
      final button = web.HTMLButtonElement()
        ..textContent = 'برای پخش صدای انتخاب‌شده لمس کن'
        ..setAttribute('aria-label', 'برای پخش صدای انتخاب‌شده لمس کن');
      button.style
        ..position = 'fixed'
        ..left = '50%'
        ..top = '50%'
        ..transform = 'translate(-50%, -50%)'
        ..zIndex = '10000'
        ..padding = '16px'
        ..borderRadius = '16px'
        ..backgroundColor = '#202535'
        ..color = 'white'
        ..font = '16px Tahoma, sans-serif';
      button.addEventListener(
        'click',
        ((web.Event _) {
          audio.currentTime = _audioTarget(video);
          audio
              .play()
              .toDart
              .then((_) {
                if (_audioTapPending == permission) {
                  _audioTapPending = null;
                  _audioTapButton = null;
                  button.remove();
                  permission.complete();
                }
              })
              .catchError((Object _) {
                button.textContent = 'پخش صدا انجام نشد؛ دوباره لمس کن';
              });
        }).toJS,
      );
      _audioTapButton = button;
      web.document.body!.appendChild(button);
      await permission.future;
    }
    if (_audio != audio) return;
    video.muted = true;
    void sync(web.Event _) {
      if (_audio != audio) return;
      audio.playbackRate = video.playbackRate;
      audio.volume = video.volume;
      final drift = audio.currentTime - _audioTarget(video);
      if (drift.abs() > .12) {
        audio.currentTime = _audioTarget(video);
      }
      if (video.paused || video.ended || video.readyState < 3) {
        audio.pause();
      } else if (audio.paused) {
        audio.play().toDart.catchError((Object _) => null);
      }
    }

    _audioVideo = video;
    _audioSync = sync.toJS;
    for (final event in _audioEvents) {
      video.addEventListener(event, _audioSync);
    }
  }

  static Future<void> ass(
    String source, {
    List<String> fonts = const [],
  }) async {
    final api = globalContext.getProperty<JSObject>('mbnAss'.toJS);
    final video = _video;
    if (video == null) throw StateError('Video unavailable');
    await api
        .callMethod<JSPromise<JSAny?>>(
          'show'.toJS,
          video,
          source.toJS,
          fonts.map((f) => f.toJS).toList().toJS,
        )
        .toDart;
  }

  static void clearAss() {
    final api = globalContext.getProperty<JSObject?>('mbnAss'.toJS);
    api?.callMethod<JSAny?>('clear'.toJS);
  }

  static web.HTMLTrackElement? _track;
  static String? _subtitleUrl;
  static String? _pendingSubtitle;
  static void clearSubtitle() {
    _pendingSubtitle = null;
    clearAss();
    _track?.remove();
    _track = null;
    if (_subtitleUrl != null) web.URL.revokeObjectURL(_subtitleUrl!);
    _subtitleUrl = null;
  }

  static void subtitle(String vtt) {
    _pendingSubtitle = vtt;
    _installSubtitle(vtt);
  }

  static void _installSubtitle(String vtt) {
    _track?.remove();
    if (_subtitleUrl != null) web.URL.revokeObjectURL(_subtitleUrl!);
    final video = _video;
    if (video == null) return;
    _subtitleUrl = web.URL.createObjectURL(
      web.Blob([vtt.toJS].toJS, web.BlobPropertyBag(type: 'text/vtt')),
    );
    _track = web.HTMLTrackElement()
      ..src = _subtitleUrl!
      ..kind = 'subtitles'
      ..srclang = 'fa'
      ..label = 'فارسی';
    video.appendChild(_track!);
    _track!.track.mode = _fullscreenVideo == video ? 'showing' : 'hidden';
  }
}
