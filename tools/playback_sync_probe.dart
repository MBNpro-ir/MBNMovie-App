// QA-only entry point. Real player and sync, isolated browser storage and
// synthetic account responses; never compile this target for distribution.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/services/device_performance.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:mbnmovie/services/network_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  MediaKit.ensureInitialized();
  DevicePerformance.configureWeb();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('player_gestures_introduced', true);
  for (var i = 0; i < 2000; i++) {
    await prefs.setInt('watch_pos_history_$i', i * 1000);
  }
  final delayed = Completer<void>(), requested = Completer<void>();
  var requests = 0;
  final auth = MbnAuth(
    client: MockClient((_) async {
      requests++;
      if (!requested.isCompleted) requested.complete();
      await delayed.future;
      return http.Response(
        jsonEncode({
          'progress': {
            'updated_at': 1000,
            'payload': {
              for (var i = 0; i < 10000; i++) 'watch_pos_remote_$i': i,
            },
          },
        }),
        200,
      );
    }),
  )..token = 'isolated-qa';
  MbnSync.instance.configure(auth: auth);
  unawaited(MbnSync.instance.syncAll());
  await requested.future;
  OfflineMode.enter();
  final episodes = [
    for (var i = 1; i <= 300; i++)
      MovieEpisode(
        id: '$i',
        name: 'قسمت $i',
        fileUrl: const String.fromEnvironment('MBN_QA_STREAM',
          defaultValue: 'https://localhost:8768/mbn-compatibility.mp4'),
      ),
  ];
  final content = MovieContent(
    id: 'qa',
    title: 'Playback QA',
    subtitle: '',
    description: '',
    year: 2026,
    rating: 0,
    kind: ContentKind.series,
    colors: const [],
    genres: const [],
    seasons: [MovieSeason(id: 's1', name: 'فصل 1 1440p', episodes: episodes)],
  );
  globalContext.setProperty(
    'mbnQaFlood'.toJS,
    (() {
      OfflineMode.leave();
      if (!delayed.isCompleted) delayed.complete();
      for (var i = 0; i < 30; i++) {
        unawaited(MbnSync.instance.syncAll());
        unawaited(MbnSync.instance.pushProgressThrottled());
      }
    }).toJS,
  );
  globalContext.setProperty(
    'mbnQaStats'.toJS,
    (() => jsonEncode({
      'requests': requests,
      'remoteApplied': prefs.containsKey('watch_pos_remote_1'),
      'offline': OfflineMode.active,
    }).toJS).toJS,
  );
  runApp(
    MaterialApp(
      theme: MovieTheme.dark,
      home: PlayerScreen(content: content, episode: episodes.first),
    ),
  );
}
