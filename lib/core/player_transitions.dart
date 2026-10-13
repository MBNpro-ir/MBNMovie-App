import 'dart:async';

/// EOF can also be reported by a failed/truncated source. Never treat that as
/// permission to advance halfway through a known episode.
bool isNaturalPlaybackEnd({
  required Duration position,
  required Duration duration,
  required bool transitioning,
  required bool seeking,
  required bool hasError,
}) =>
    !transitioning &&
    !seeking &&
    !hasError &&
    duration > Duration.zero &&
    position > Duration.zero &&
    position >= duration - const Duration(seconds: 2);

Duration playbackResumeTarget(Duration requested, Duration duration) {
  if (duration <= Duration.zero) return requested;
  if (duration <= const Duration(seconds: 2)) return Duration.zero;
  final last = duration - const Duration(seconds: 2);
  return requested > last ? last : requested;
}

/// Commands acknowledge submission, not decoder seek completion. Verify the
/// clock after the first play (some decoders reset it), and retry at most once.
/// A failed restore aborts the transition so the caller rolls back, rather than
/// committing a quality whose playback silently starts at zero.
Future<Duration> restorePlaybackPosition({
  required Duration requested,
  required Duration Function() duration,
  required Duration Function() position,
  required Future<void> Function(Duration) seek,
  required Future<void> Function() start,
  required bool Function() active,
  required bool playing,
  Future<void> Function(Duration)? wait,
}) async {
  final delay = wait ?? Future<void>.delayed;
  void check() {
    if (!active()) throw StateError('superseded playback operation');
  }

  check();
  var target = playbackResumeTarget(requested, duration());
  if (target > Duration.zero) await seek(target);
  check();
  if (playing) await start();
  check();
  if (target <= Duration.zero) return target;
  for (var attempt = 0; attempt < 2; attempt++) {
    // Give the post-play clock reset time to arrive before accepting a seek.
    for (var tick = 0; tick < 8; tick++) {
      await delay(const Duration(milliseconds: 100));
      check();
    }
    target = playbackResumeTarget(requested, duration());
    final delta = position() - target;
    if (delta >= -const Duration(seconds: 2) &&
        delta <=
            (playing
                ? const Duration(seconds: 6)
                : const Duration(seconds: 2))) {
      return target;
    }
    if (attempt == 0) {
      await seek(target);
      check();
    }
  }
  throw StateError('playback position was not restored');
}
