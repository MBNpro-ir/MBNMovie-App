import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mbnmovie/core/watch_progress.dart';
import 'package:mbnmovie/core/episode_catalog.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/episode_picker_screen.dart';

const content = MovieContent(
  id: 'audit',
  title: 'Audit',
  subtitle: '',
  description: '',
  year: 2026,
  rating: 8,
  kind: ContentKind.series,
  colors: [Colors.blue],
  genres: [],
  seasons: [
    MovieSeason(
      id: 'season1',
      name: 'فصل 1 720p',
      episodes: [
        MovieEpisode(
          id: '1',
          name: 'قسمت اول',
          fileUrl: 'https://example.com/1.mkv',
        ),
      ],
    ),
  ],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    MbnSync.instance.clear();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    MbnSync.instance.clear();
  });
  testWidgets('open episode picker reflects a later server watched marker', (
    tester,
  ) async {
    final group = EpisodeCatalog.from(content).episodes.first;
    bool remote = false;
    final auth = MbnAuth(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'progress': {
              'payload': remote
                  ? {
                      'watch_pos_audit_${group.id}': 3000000,
                      'watch_dur_audit_${group.id}': 3000000,
                      'watch_done_audit_${group.id}': true,
                      'watch_time_audit_${group.id}': 2000,
                    }
                  : <String, dynamic>{},
              'updated_at': remote ? 2000 : 1000,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..token = 'audit-only';
    MbnSync.instance.configure(auth: auth);
    await MbnSync.instance.syncProgressIfStale();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: EpisodePickerScreen(content: content, onPlay: (_, _) async {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تماشا نشده'), findsOneWidget);
    remote = true;

    await tester.runAsync(() async {
      await MbnSync.instance.syncAll();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pumpAndSettle();
    expect(
      (await WatchProgressStore().load(
        contentId: content.id,
        episodeId: group.id,
      ))!.watched,
      isTrue,
    );
    expect(find.text('تماشا نشده'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
