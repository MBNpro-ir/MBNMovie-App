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

  static Future<bool> fullscreen(bool value) async {
    try {
      if (!value) {
        final video = _video;
        if (video != null &&
            video.hasProperty('webkitExitFullscreen'.toJS).toDart) {
          video.callMethod<JSAny?>('webkitExitFullscreen'.toJS);
        }
        if (web.document.fullscreenElement != null) {
          await web.document.exitFullscreen().toDart;
        }
        return false;
      }
      if (web.document.fullscreenEnabled) {
        await web.document.documentElement!.requestFullscreen().toDart;
        return true;
      }
      final video = _video;
      if (video != null &&
          video.hasProperty('webkitEnterFullscreen'.toJS).toDart) {
        if (_track != null) _track!.track.mode = 'showing';
        video.addEventListener(
          'webkitendfullscreen',
          ((web.Event e) {
            if (_track != null) _track!.track.mode = 'hidden';
          }).toJS,
        );
        video.callMethod<JSAny?>('webkitEnterFullscreen'.toJS);
        return true;
      }
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
    final video = _video;
    if (video != null) {
      video.pause();
      video.removeAttribute('src');
      video.load();
    }
    unawaited(fullscreen(false));
  }

  static web.HTMLAudioElement? _audio;
  static void clearAudio() {
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
    if (!video.paused) await audio.play().toDart;
    video.muted = true;
    void sync(web.Event _) {
      if (_audio != audio) return;
      audio.playbackRate = video.playbackRate;
      if ((audio.currentTime - video.currentTime).abs() > .4) {
        audio.currentTime = video.currentTime;
      }
      if (video.paused) {
        audio.pause();
      } else if (audio.paused) {
        audio.play().toDart.catchError((Object _) => null);
      }
    }

    for (final event in [
      'play',
      'pause',
      'seeked',
      'ratechange',
      'timeupdate',
    ]) {
      video.addEventListener(event, sync.toJS);
    }
  }

  static web.HTMLTrackElement? _track;
  static String? _subtitleUrl;
  static void subtitle(String vtt) {
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
    _track!.track.mode = 'hidden';
  }
}
