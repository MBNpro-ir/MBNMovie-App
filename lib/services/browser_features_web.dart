import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

abstract final class BrowserFeatures {
  static bool get isMobileBrowser {
    final nav = web.window.navigator;
    final ua = nav.userAgent.toLowerCase();
    return RegExp(r'android|iphone|ipad|ipod|mobile').hasMatch(ua) ||
        (ua.contains('macintosh') && nav.maxTouchPoints > 1);
  }

  static bool get castSupported =>
      _video != null &&
      (_video!.hasProperty('webkitShowPlaybackTargetPicker'.toJS).toDart ||
          _video!.getProperty<JSObject?>('remote'.toJS) != null);

  static bool get requiresCompatibleVideo =>
      web.window.navigator.vendor.contains('Apple');
  static web.HTMLVideoElement? get _video =>
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

  static Future<void> externalAudio(String url) async {
    clearAudio();
    final video = _video;
    if (video == null) throw StateError('No video');
    final audio = web.HTMLAudioElement()
      ..src = url
      ..preload = 'auto';
    _audio = audio;
    web.document.body!.appendChild(audio);
    audio.currentTime = video.currentTime;
    audio.playbackRate = video.playbackRate;
    audio.volume = video.volume;
    try {
      if (!video.paused) await audio.play().toDart;
    } catch (_) {
      if (_audio == audio) clearAudio();
      rethrow;
    }
    if (_audio != audio) return;
    video.muted = true;
    void sync(web.Event _) {
      if (_audio != audio) return;
      audio.playbackRate = video.playbackRate;
      audio.volume = video.volume;
      if ((audio.currentTime - video.currentTime).abs() > .4) {
        audio.currentTime = video.currentTime;
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

  static web.HTMLTrackElement? _track;
  static String? _subtitleUrl;
  static void clearSubtitle() {
    _track?.remove();
    _track = null;
    if (_subtitleUrl != null) web.URL.revokeObjectURL(_subtitleUrl!);
    _subtitleUrl = null;
  }

  static void subtitle(String vtt) {
    clearSubtitle();
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
    _track!.track.mode = 'hidden';
  }
}
