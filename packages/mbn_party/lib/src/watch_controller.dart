import 'dart:async';

import 'package:flutter/widgets.dart';

import 'client.dart';

/// Small adapter keeps synchronization independent of media_kit/browser.
class PartyPlayback {
  const PartyPlayback({
    required this.position,
    required this.duration,
    required this.playing,
    required this.buffering,
    required this.rate,
    required this.seek,
    required this.play,
    required this.pause,
    required this.setRate,
    required this.playingChanges,
    required this.positionChanges,
    required this.rateChanges,
  });
  final Duration Function() position, duration;
  final bool Function() playing, buffering;
  final double Function() rate;
  final Future<void> Function(Duration) seek;
  final Future<void> Function() play, pause;
  final Future<void> Function(double) setRate;
  final Stream<bool> playingChanges;
  final Stream<Duration> positionChanges;
  final Stream<double> rateChanges;
}

class WatchPartyController extends ChangeNotifier with WidgetsBindingObserver {
  WatchPartyController({
    required this.client,
    required this.sessionId,
    required this.playback,
  }) {
    WidgetsBinding.instance.addObserver(this);
  }
  final PartyClient client;
  final String sessionId;
  final PartyPlayback playback;
  final String clientId = partyNonce();
  PartyJson snapshot = {};
  String status = 'در حال پیوستن به پارتی…';
  bool connected = true, closed = false, prepared = false;
  bool _disposed = false, _polling = false, _sending = false, _applying = false;
  bool _registered = false, _mediaTransition = false, _foreground = true;
  int _suppressedUntil = 0, _lastHeartbeat = 0, _lastCorrection = 0;
  int? _lastPosition, _lastPositionAt;
  Timer? _pollTimer, _startTimer, _seekTimer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void>? _joining;
  int get version => partyInt(snapshot['version']);
  bool get waiting => snapshot.isEmpty || snapshot['state'] == 'waiting';
  int get participants => (snapshot['participants'] as List?)?.length ?? 0;
  String get actorName =>
      (snapshot['actor'] as Map?)?['name']?.toString() ?? 'یکی از دوستان';

  Future<void> join() => _joining ??= _join();
  Future<void> _join() async {
    if (!_registered) {
      client.activePlayers++;
      _registered = true;
    }
    try {
      snapshot = await client.command(sessionId, 'join', clientId: clientId);
      if (_disposed) return;
      _describe();
      _schedule();
    } on PartyException catch (e) {
      _failed(e);
    }
  }

  Future<void> ready() async {
    await join();
    if (_disposed || closed || snapshot.isEmpty) return;
    final duration = playback.duration().inMilliseconds;
    if (duration <= 0) {
      status = 'در انتظار آماده‌شدن ویدیو…';
      notifyListeners();
      _schedule();
      return;
    }
    _suppress();
    await playback.pause();
    try {
      final result = await client.command(
        sessionId,
        'ready',
        clientId: clientId,
        duration: duration,
      );
      if (_disposed) return;
      prepared = true;
      _listen();
      await _accept(result, force: true);
    } on PartyException catch (e) {
      _failed(e);
    }
  }

  void _listen() {
    if (_subscriptions.isNotEmpty) return;
    _subscriptions.add(
      playback.playingChanges.listen((playing) {
        if (_localAllowed) unawaited(control(playing ? 'play' : 'pause'));
      }),
    );
    _subscriptions.add(
      playback.rateChanges.listen((rate) {
        if (_localAllowed) unawaited(control('rate', rate: rate.clamp(.5, 2)));
      }),
    );
    _subscriptions.add(
      playback.positionChanges.listen((position) {
        final now = client.clock.localNow, value = position.inMilliseconds;
        if (_lastPosition != null &&
            _lastPositionAt != null &&
            _localAllowed &&
            !playback.buffering()) {
          final expected =
              _lastPosition! +
              (playback.playing()
                  ? ((now - _lastPositionAt!) * playback.rate()).round()
                  : 0);
          if ((value - expected).abs() > 1200) {
            _seekTimer?.cancel();
            _seekTimer = Timer(
              const Duration(milliseconds: 180),
              () => unawaited(
                control('seek', position: playback.position().inMilliseconds),
              ),
            );
          }
        }
        _lastPosition = value;
        _lastPositionAt = now;
      }),
    );
  }

  bool get _localAllowed =>
      !_disposed &&
      !closed &&
      prepared &&
      !waiting &&
      !_applying &&
      !_sending &&
      !_mediaTransition &&
      client.clock.localNow >= _suppressedUntil;
  void _suppress([int milliseconds = 1200]) {
    _suppressedUntil = client.clock.localNow + milliseconds;
  }

  void suspendLocalChanges() {
    _mediaTransition = true;
    _suppress(15000);
    _startTimer?.cancel();
  }

  void resumeLocalChanges() {
    _mediaTransition = false;
    _suppress();
    if (prepared) unawaited(_apply(force: true));
  }

  Future<void> control(String action, {int? position, double? rate}) async {
    if (_disposed || closed || waiting || _sending || !prepared) return;
    _sending = true;
    _suppress();
    try {
      final result = await client.command(
        sessionId,
        action,
        clientId: clientId,
        version: version,
        position: position ?? playback.position().inMilliseconds,
        rate: rate,
      );
      if (!_disposed) await _accept(result, force: true);
    } on PartyException catch (e) {
      if (_disposed) return;
      if (e.code == 'version_conflict' && e.data['session'] is Map) {
        await _accept(
          Map<String, dynamic>.from(e.data['session'] as Map),
          force: true,
        );
      } else {
        _failed(e);
      }
    } finally {
      _sending = false;
    }
  }

  void _schedule() {
    _pollTimer?.cancel();
    if (!_disposed && !closed && _foreground) {
      _pollTimer = Timer(
        Duration(milliseconds: connected ? 1000 : 4000),
        _poll,
      );
    }
  }

  Future<void> _poll({bool force = false}) async {
    if (_disposed || _polling || closed) return;
    _polling = true;
    try {
      if (snapshot.isEmpty) {
        snapshot = await client.command(sessionId, 'join', clientId: clientId);
        if (!prepared && playback.duration() > Duration.zero) {
          _joining = Future.value();
          await ready();
        }
      }
      final now = client.clock.localNow;
      final value = now - _lastHeartbeat >= 10000
          ? await client.command(sessionId, 'heartbeat', clientId: clientId)
          : await client.session(sessionId);
      if (now - _lastHeartbeat >= 10000) _lastHeartbeat = now;
      if (!_disposed) {
        await _accept(value, force: force);
        if (!prepared && playback.duration() > Duration.zero) await ready();
      }
    } on PartyException catch (e) {
      if (!_disposed) {
        if (e.code == 'join_required') {
          snapshot = {};
          prepared = false;
          _joining = null;
        }
        _failed(e);
      }
    } finally {
      _polling = false;
      _schedule();
    }
  }

  Future<void> _accept(PartyJson value, {bool force = false}) async {
    if (_disposed) return;
    // A slow heartbeat may complete after a newer control response.
    if (snapshot.isNotEmpty && partyInt(value['version']) < version) return;
    final changed = version != partyInt(value['version']) || !connected;
    snapshot = value;
    connected = true;
    if (value['state'] == 'closed') {
      closed = true;
      _startTimer?.cancel();
      _pollTimer?.cancel();
      status = 'پارتی بسته شد؛ می‌توانی مستقل ادامه بدهی.';
      notifyListeners();
      return;
    }
    if (prepared && !_sending) {
      await _apply(force: force || changed);
    } else if (prepared && force) {
      await _apply(force: true);
    }
    if (changed || force) {
      _describe();
      notifyListeners();
    }
  }

  Future<void> _apply({bool force = false}) async {
    if (_disposed ||
        !prepared ||
        closed ||
        snapshot.isEmpty ||
        _applying ||
        _mediaTransition) {
      return;
    }
    final state = snapshot['state'];
    final target = client.clock.position(snapshot);
    final drift = (target - playback.position().inMilliseconds).abs();
    final now = client.clock.localNow;
    if (!force &&
        (drift < 1800 ||
            now - _lastCorrection < 12000 ||
            playback.buffering())) {
      return;
    }
    _applying = true;
    _suppress();
    _startTimer?.cancel();
    try {
      final speed = (snapshot['rate'] as num?)?.toDouble() ?? 1;
      if ((playback.rate() - speed).abs() > .001) await playback.setRate(speed);
      if (state == 'waiting' || state == 'paused') {
        if (playback.playing()) await playback.pause();
        if (force && drift > 250) {
          await playback.seek(Duration(milliseconds: target));
        }
      } else if (state == 'playing') {
        final delay = partyInt(snapshot['anchor_ms']) - client.clock.serverNow;
        if (delay > 0) {
          if (playback.playing()) await playback.pause();
          await playback.seek(Duration(milliseconds: target));
          if (_disposed) return;
          final revision = version;
          _startTimer = Timer(
            Duration(
              milliseconds:
                  (partyInt(snapshot['anchor_ms']) - client.clock.serverNow)
                      .clamp(0, 10000),
            ),
            () {
              if (!_disposed && version == revision && !closed) {
                _suppress();
                unawaited(
                  playback.play().catchError((Object _) {
                    status = 'برای شروع پخش، دکمهٔ پخش را لمس کن.';
                    if (!_disposed) notifyListeners();
                  }),
                );
              }
            },
          );
        } else {
          if (drift > (force ? 350 : 1800)) {
            await playback.seek(Duration(milliseconds: target));
            _lastCorrection = now;
          }
          if (!_disposed && !playback.playing()) await playback.play();
        }
      }
    } catch (_) {
      if (!_disposed) {
        status =
            'پخش آماده نشد؛ دکمهٔ پخش را لمس کن یا دوباره به پارتی بپیوند.';
        notifyListeners();
      }
    } finally {
      _applying = false;
      _suppress();
    }
  }

  void _describe() {
    status = switch (snapshot['state']) {
      'waiting' => 'منتظر پیوستن و آماده‌شدن دوستت…',
      'paused' => 'پخش توسط $actorName متوقف شد',
      'playing' =>
        partyInt(snapshot['anchor_ms']) > client.clock.serverNow
            ? 'همه آماده‌اند؛ شروع هم‌زمان…'
            : 'با هم تماشا می‌کنید · $participants نفر',
      _ => 'در حال اتصال به پارتی…',
    };
  }

  void _failed(PartyException error) {
    if (_disposed) return;
    connected = false;
    status = error.message;
    if ([401, 403, 404, 410].contains(error.status)) {
      closed = true;
      _pollTimer?.cancel();
      _startTimer?.cancel();
    }
    notifyListeners();
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _pollTimer?.cancel();
      _startTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(_poll(force: true));
    }
  }

  Future<void> leave({bool end = false}) async {
    if (_disposed || closed) return;
    try {
      await client.command(
        sessionId,
        end ? 'end' : 'leave',
        clientId: clientId,
      );
    } on PartyException catch (e) {
      if (e.status != 410) rethrow;
    }
    closed = true;
    _pollTimer?.cancel();
    _startTimer?.cancel();
    status = 'از پارتی خارج شدی.';
    if (!_disposed) notifyListeners();
    unawaited(client.refresh());
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pollTimer?.cancel();
    _startTimer?.cancel();
    _seekTimer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_registered) {
      client.activePlayers = (client.activePlayers - 1).clamp(0, 100);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
