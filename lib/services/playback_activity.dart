import 'dart:async';
import 'package:flutter/foundation.dart';

/// Suspend optional work without destroying the pages beneath the player.
abstract final class PlaybackActivity {
  static final changes = ValueNotifier<bool>(false);
  static int _holds = 0;
  static bool _settling = false;
  static Timer? _resume;
  static bool get active => _holds > 0 || _settling;

  static void _publish() => scheduleMicrotask(() {
    if (changes.value != active) changes.value = active;
  });

  static VoidCallback hold() {
    _resume?.cancel();
    _settling = false;
    _holds++;
    _publish();
    var released = false;
    return () {
      if (released) return;
      released = true;
      _holds--;
      if (_holds > 0) return;
      // Let Back finish its route transition before shelves/sync resume.
      _settling = true;
      _resume = Timer(const Duration(milliseconds: 550), () {
        _settling = false;
        _publish();
      });
    };
  }

  static Future<void> whenIdle() {
    if (!active) return Future.value();
    final completer = Completer<void>();
    void listener() {
      if (active) return;
      changes.removeListener(listener);
      completer.complete();
    }

    changes.addListener(listener);
    return completer.future;
  }
}
