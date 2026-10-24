// Native core + actual app DropTarget callback; the Windows Explorer gesture
// remains a separate manual acceptance step.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

class _Paths extends PathProviderWindows {
  _Paths(this.path);
  final String path;
  @override
  Future<String> getApplicationSupportPath() async => path;
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Windows external tracks activate, persist, restore and discard missing file',
    (tester) async {
      const directory = String.fromEnvironment('MBN_QA_TRACK_DIR');
      final media = File('$directory/clip.mp4'),
          sub = File('$directory/external-fa.srt'),
          audio = File('$directory/external-audio.wav');
      expect(
        media.existsSync() && sub.existsSync() && audio.existsSync(),
        true,
      );
      final temp = await Directory.systemTemp.createTemp(
        'mbn-tracks-integration-',
      );
      final subtitle = await sub.copy('${temp.path}/drag-fa.srt'),
          audioFile = await audio.copy('${temp.path}/drag-audio.wav');
      SharedPreferencesStorePlatform.instance = SharedPreferencesWindows()
        ..pathProvider = _Paths(temp.path);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('player_gestures_introduced', true);
      MediaKit.ensureInitialized();
      await windowManager.ensureInitialized();
      final episode = MovieEpisode(id: 'one', name: '1', fileUrl: media.path);
      final item = MovieContent(
        id: 'external-qa',
        title: 'External file QA',
        subtitle: '',
        description: '',
        year: 2026,
        rating: 0,
        kind: ContentKind.movie,
        colors: const [],
        genres: const [],
        seasons: [
          MovieSeason(id: 'season', name: 'فیلم', episodes: [episode]),
        ],
      );
      Future<Player> open(int key) async {
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(key),
            theme: MovieTheme.dark,
            home: PlayerScreen(content: item, episode: episode),
          ),
        );
        await _until(tester, () => find.byType(Video).evaluate().isNotEmpty);
        final p = tester.widget<Video>(find.byType(Video)).controller.player;
        await _until(
          tester,
          () => p.state.position > const Duration(milliseconds: 300),
        );
        return p;
      }

      Future<List<dynamic>> tracks(Player p) async =>
          jsonDecode(
                await (p.platform as NativePlayer).getProperty('track-list'),
              )
              as List;
      Future<void> close() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }

      var player = await open(1);
      final drop = tester.widget<DropTarget>(find.byType(DropTarget));
      expect(drop.enable, true);
      drop.onDragDone!(
        DropDoneDetails(
          files: [DropItemFile(subtitle.path), DropItemFile(audioFile.path)],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await _until(
        tester,
        () => prefs
            .getKeys()
            .where((k) => k.startsWith('external_tracks_v1_'))
            .any((k) => jsonDecode(prefs.getString(k)!)['tracks'].length == 2),
      );
      var list = await tracks(player);
      expect(list.where((r) => r['external'] == true).length, 2);
      expect(player.state.track.audio.id, isNot('auto'));
      expect(player.state.track.subtitle.id, isNot('auto'));
      final selectedAudio = player.state.track.audio.id,
          selectedSubtitle = player.state.track.subtitle.id;
      expect(selectedSubtitle, isNot('no'));
      expect(selectedAudio, isNot('no'));
      await close();
      player = await open(2);
      await _until(
        tester,
        () =>
            player.state.track.subtitle.id != 'auto' &&
            player.state.track.subtitle.id != 'no',
      );
      list = await tracks(player);
      expect(list.where((r) => r['external'] == true).length, 2);
      expect(
        list.any(
          (r) =>
              r['type'] == 'audio' &&
              r['external'] == true &&
              r['selected'] == true,
        ),
        true,
      );
      expect(
        list.any(
          (r) =>
              r['type'] == 'sub' &&
              r['external'] == true &&
              r['selected'] == true,
        ),
        true,
      );
      await close();
      await subtitle.delete();
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey(3),
          theme: MovieTheme.dark,
          home: PlayerScreen(content: item, episode: episode),
        ),
      );
      await _until(
        tester,
        () => find.text('فایل زیرنویس پیدا نشد').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('ادامه با پیش‌فرض'));
      await tester.pump();
      await _until(
        tester,
        () => prefs
            .getKeys()
            .where((k) => k.startsWith('external_tracks_v1_'))
            .any((k) => jsonDecode(prefs.getString(k)!)['tracks'].length == 1),
      );
      await close();
      expect(tester.takeException(), isNull);
    },
  );
}
