import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/player_exit.dart';

void main() {
  test(
    'Back navigates while sync and fullscreen are stalled, then completes save',
    () async {
      final disk = Completer<void>(),
          network = Completer<void>(),
          fullscreen = Completer<void>();
      var navigated = false, saved = false, uploaded = false;
      exitPlayerWithoutWaiting(
        saveCheckpoint: () async {
          await disk.future;
          saved = true;
          await network.future;
          uploaded = true;
        },
        restoreSystemUi: () => fullscreen.future,
        navigateBack: () => navigated = true,
      );
      expect(navigated, isTrue);
      expect(saved, isFalse);
      disk.complete();
      await Future<void>.delayed(Duration.zero);
      expect(saved, isTrue);
      expect(uploaded, isFalse);
      network.complete();
      fullscreen.complete();
      await Future<void>.delayed(Duration.zero);
      expect(uploaded, isTrue);
    },
  );
  test(
    'synchronous cleanup failures never trap Back or become unhandled',
    () async {
      var navigations = 0;
      exitPlayerWithoutWaiting(
        saveCheckpoint: () => throw StateError('disk'),
        restoreSystemUi: () => throw StateError('platform'),
        navigateBack: () => navigations++,
      );
      await Future<void>.delayed(Duration.zero);
      expect(navigations, 1);
    },
  );
}
