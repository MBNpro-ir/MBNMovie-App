import 'dart:math';

/// Counts real playback; seeking, pauses and stalls do not earn watch time.
class WatchClock {
  WatchClock({int Function()? now}) {
    final clock = Stopwatch()..start();
    _now = now ?? (() => clock.elapsedMilliseconds);
  }
  late final int Function() _now;
  int? _lastTime, _lastPosition;
  bool _wasActive = false;
  int _pending = 0;
  int get pending => _pending;
  void tick(Duration position, {required bool active, required double rate}) {
    final now = _now();
    final previous = _lastTime, previousPosition = _lastPosition;
    final previouslyActive = _wasActive;
    _lastTime = now;
    _lastPosition = position.inMilliseconds;
    _wasActive = active;
    if (!active ||
        !previouslyActive ||
        rate <= 0 ||
        !rate.isFinite ||
        previous == null ||
        previousPosition == null) {
      return;
    }
    final elapsed = now - previous;
    final moved = position.inMilliseconds - previousPosition;
    if (elapsed <= 0 ||
        elapsed > 2500 ||
        moved <= 0 ||
        moved > elapsed * rate + 750) {
      return;
    }
    _pending += min(elapsed, (moved / rate).round());
  }

  int take() {
    final value = _pending;
    _pending = 0;
    return value;
  }
}
