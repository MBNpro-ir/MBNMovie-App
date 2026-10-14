import 'dart:async';

/// Navigation must not depend on disk/network or a platform fullscreen promise.
/// Both cleanups start immediately and contain failures independently.
void exitPlayerWithoutWaiting({
  required Future<void> Function() saveCheckpoint,
  required Future<void> Function() restoreSystemUi,
  required void Function() navigateBack,
}) {
  unawaited(Future<void>.sync(saveCheckpoint).catchError((Object _) {}));
  unawaited(Future<void>.sync(restoreSystemUi).catchError((Object _) {}));
  navigateBack();
}
