// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/detail_screen.dart';

class _ProbePaths extends PathProviderWindows {
  _ProbePaths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitle('MBNMovie Frame QA');
  final temp = await Directory.systemTemp.createTemp('mbn-real-scheduler-');
  // Isolate this diagnostic process from the running app's account/history.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
    ..pathProvider = _ProbePaths(temp.path);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('player_decoder_mode',
      Platform.environment['MBN_QA_DECODER'] ?? 'hardware');
  await prefs.setBool('player_gestures_introduced', true);
  final source =
      Platform.environment['MBN_QA_MEDIA'] ??
      const String.fromEnvironment('MBN_QA_MEDIA');
  var media = source;
  if (Platform.environment['MBN_QA_CURRENT_STREAM'] == 'true' ||
      const bool.fromEnvironment('MBN_QA_CURRENT_STREAM')) {
    final saved =
        jsonDecode(
              await File(
                '${Platform.environment['APPDATA']}/com.mbn/MBNMovie/shared_preferences.json',
              ).readAsString(),
            )
            as Map;
    final last = jsonDecode(saved['flutter.watch_last_v1'] as String) as Map;
    media = last['fileUrl'] as String;
    for (final entry in saved.entries) {
      final key = entry.key as String;
      if (key.startsWith('flutter.sub_')) {
        final name = key.substring(8), value = entry.value;
        if (value is bool) await prefs.setBool(name, value);
        if (value is String) await prefs.setString(name, value);
        if (value is int) await prefs.setInt(name, value);
        if (value is double) await prefs.setDouble(name, value);
      }
    }
  }
  final content = MovieContent(
    id: 'isolated-frame-probe',
    title: 'Windows frame timing QA',
    subtitle: '',
    description: '',
    year: 2026,
    rating: 0,
    kind: ContentKind.movie,
    colors: const [],
    genres: const [],
  );
  await windowManager.show();
  await windowManager.setSize(const Size(960, 600));
  runApp(
    MaterialApp(
      theme: MovieTheme.dark,
      home: PlayerScreen(
        content: content,
        episode: MovieEpisode(id: 'qa', name: 'QA', fileUrl: media),
      ),
    ),
  );
  final timings = <FrameTiming>[];
  WidgetsBinding.instance.addTimingsCallback(timings.addAll);
  Player? player;
  void visit(Element element) {
    if (element.widget case Video video) player = video.controller.player;
    element.visitChildren(visit);
  }

  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    if (player != null && player!.state.position.inMilliseconds >= 200) break;
  }
  final p = player!;
  final native = p.platform as NativePlayer;
  final rows = <Map<String, Object?>>[];
  final seconds =
      int.tryParse(Platform.environment['MBN_QA_SECONDS'] ?? '') ?? 20;
  final start = Stopwatch()..start();
  var previousFrames = 0;
  final nativeOptions =
      jsonDecode(Platform.environment['MBN_QA_OPTIONS'] ?? '{}') as Map;
  for (final entry in nativeOptions.entries) {
    await native.setProperty(entry.key as String, entry.value as String);
  }
  if (Platform.environment['MBN_QA_LOOP'] == 'true') {
    await native.setProperty('loop-file', 'inf');
  }
  for (var i = 0; i < seconds * 2; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final row = <String, Object?>{
      'tick': i,
      'elapsedMs': start.elapsedMilliseconds,
      'positionMs': p.state.position.inMilliseconds,
      'buffering': p.state.buffering,
      'frameworkFrames': timings.length - previousFrames,
      'maxBuildMs': timings
          .skip(previousFrames)
          .fold<double>(
            0,
            (n, f) => n > f.buildDuration.inMicroseconds / 1000
                ? n
                : f.buildDuration.inMicroseconds / 1000,
          ),
      'maxRasterMs': timings
          .skip(previousFrames)
          .fold<double>(
            0,
            (n, f) => n > f.rasterDuration.inMicroseconds / 1000
                ? n
                : f.rasterDuration.inMicroseconds / 1000,
          ),
    };
    previousFrames = timings.length;
    for (final key in [
      'mpv-version',
      'hwdec',
      'video-codec',
      'container-fps',
      'hwdec-current',
      'current-vo',
      'frame-drop-count',
      'decoder-frame-drop-count',
      'vo-delayed-frame-count',
      'mistimed-frame-count',
      'avsync',
      'demuxer-cache-duration',
      'display-fps',
      'estimated-display-fps',
      'cache-speed',
      'demuxer-cache-state',
      'audio-buffer',
      'audio-pts',
      'video-pts',
      'vsync-jitter',
      'video-timing-offset',
      'video-sync',
    ]) {
      try {
        row[key] = await native.getProperty(key);
      } catch (_) {
        row[key] = null;
      }
    }
    rows.add(row);
    if (i % 20 == 0) {
      stdout.writeln('MBN_QA_PROGRESS ${jsonEncode(row)}');
    }
  }
  double maxMs(Iterable<Duration> values) => values.fold<double>(
    0,
    (a, b) => a > b.inMicroseconds / 1000 ? a : b.inMicroseconds / 1000,
  );
  final result = {
    'rows': rows,
    'frameworkFrames': timings.length,
    'maxBuildMs': maxMs(timings.map((f) => f.buildDuration)),
    'maxRasterMs': maxMs(timings.map((f) => f.rasterDuration)),
  };
  final output =
      Platform.environment['MBN_QA_OUTPUT'] ??
      const String.fromEnvironment('MBN_QA_OUTPUT');
  await File(output).writeAsString(jsonEncode(result));
  stdout.writeln(
    'MBN_REAL_SCHEDULER ${jsonEncode({'first': rows.first, 'last': rows.last, 'frameworkFrames': timings.length, 'maxRasterMs': result['maxRasterMs']})}',
  );
  runApp(const SizedBox.shrink());
  await Future<void>.delayed(const Duration(seconds: 1));
  await temp.delete(recursive: true);
  exit(0);
}
