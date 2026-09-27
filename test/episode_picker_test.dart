import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/screens/episode_picker_screen.dart';
import 'package:mbnmovie/core/watch_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mbnmovie/widgets/smart_cast_sheet.dart';

const content = MovieContent(
  id: 'test',
  title: 'عنوان آزمایشی',
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
      name: 'فصل 1 زیرنویس 720p',
      episodes: [
        MovieEpisode(
          id: '1',
          name: 'قسمت اول',
          fileUrl: 'https://example.com/1.mkv',
          fileType: 'mkv',
          fileSize: '345',
        ),
        MovieEpisode(
          id: '2',
          name: 'قسمت دوم',
          fileUrl: 'https://example.com/2.mkv',
          fileType: 'mkv',
          fileSize: '345',
        ),
      ],
    ),
    MovieSeason(
      id: 'season1-1080',
      name: 'فصل 1 زیرنویس 1080p',
      episodes: [
        MovieEpisode(
          id: '101',
          name: 'قسمت اول',
          fileUrl: 'https://example.com/1-1080.mkv',
          fileType: 'mkv',
          fileSize: '680',
        ),
        MovieEpisode(
          id: '102',
          name: 'قسمت دوم',
          fileUrl: 'https://example.com/2-1080.mkv',
          fileType: 'mkv',
          fileSize: '690',
        ),
      ],
    ),
  ],
);

const trailerContent = MovieContent(
  id: 'trailer-test',
  title: 'عنوان تیزر',
  subtitle: '',
  description: '',
  year: 2026,
  rating: 8,
  kind: ContentKind.series,
  colors: [Colors.blue],
  genres: [],
  seasons: [
    MovieSeason(
      id: 'season1-720',
      name: 'فصل 1 زیرنویس 720p',
      episodes: [
        MovieEpisode(
          id: '1',
          name: 'قسمت 1',
          fileUrl: 'https://example.com/1.mkv',
        ),
      ],
    ),
    MovieSeason(
      id: 'trailer',
      name: 'تیزر',
      episodes: [
        MovieEpisode(
          id: 't1',
          name: 'تیزر',
          fileUrl: 'https://example.com/trailer.mkv',
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets('trailer season hides the unknown quality label', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: EpisodePickerScreen(
            content: trailerContent,
            onPlay: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // فصل عادی: چیپ کیفیت واقعی دیده می‌شود.
    expect(find.text('720p'), findsWidgets);
    // رفتن به فصل تیزرها.
    await tester.tap(find.text('تیزرها'));
    await tester.pumpAndSettle();
    // هیچ‌جا «بدون برچسب کیفیت» نباید دیده شود؛ نه چیپ، نه بج کارت.
    expect(find.text('بدون برچسب کیفیت'), findsNothing);
    expect(find.text('تیزر'), findsWidgets);
  });
  testWidgets('first TV destination page has working visible back control', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSmartCastSheet(
                context,
                content: content,
                episode: content.seasons.first.episodes.first,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('بازگشت'), findsOneWidget);
    await tester.tap(find.text('بازگشت'));
    await tester.pumpAndSettle();
    expect(find.text('نوع تلویزیون را انتخاب کن'), findsNothing);
  });
  for (final size in [const Size(390, 844), const Size(1024, 768)]) {
    testWidgets('episode grid and destination menu at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: EpisodePickerScreen(
              content: content,
              onPlay: (_, _) async {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text('پخش'), findsNWidgets(2));
      expect(find.byTooltip('دانلود با انتخاب کیفیت'), findsNWidgets(2));
      expect(find.byType(Image), findsNothing);
      expect(find.text('تماشا نشده'), findsNWidgets(2));
      expect(find.text('720p'), findsWidgets);
      expect(find.text('1080p'), findsWidgets);
      final first = tester.getCenter(find.text('قسمت اول'));
      final second = tester.getCenter(find.text('قسمت دوم'));
      expect(first.dy, second.dy);
      await tester.tap(find.text('پخش').first);
      await tester.pumpAndSettle();
      expect(find.text('پلیر داخلی (پیشنهادی)'), findsOneWidget);
      expect(find.text('پلیرهای خارجی'), findsOneWidget);
      expect(find.text('تلویزیون یا مانیتور بدون سیم'), findsOneWidget);
      expect(find.text('بازگشت'), findsNothing);
      await tester.tap(find.text('تلویزیون یا مانیتور بدون سیم'));
      await tester.pumpAndSettle();
      expect(find.text('پخش مستقیم روی تلویزیون'), findsOneWidget);
      expect(find.text('بازگشت').hitTestable(), findsOneWidget);
      await tester.tap(find.text('پخش مستقیم روی تلویزیون'));
      await tester.pumpAndSettle();
      expect(find.text('نوع تلویزیون را انتخاب کن'), findsOneWidget);
      await tester.tap(find.text('بازگشت').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('نوع تلویزیون را انتخاب کن'), findsNothing);
      expect(
        find.text('پخش مستقیم روی تلویزیون').hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('بازگشت').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('پخش مستقیم روی تلویزیون'), findsNothing);
      expect(find.text('کجا پخش شود؟'), findsOneWidget);
      expect(find.text('بازگشت'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('large text falls back to readable single-column cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: EpisodePickerScreen(content: content, onPlay: (_, _) async {}),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('watched episode has a distinct card and visible label', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await WatchProgressStore().save(
      contentId: content.id,
      episodeId: '1',
      position: const Duration(minutes: 22),
      duration: const Duration(minutes: 24),
      markWatched: true,
    );
    await WatchProgressStore().save(
      contentId: content.id,
      episodeId: '2',
      position: const Duration(minutes: 19),
      duration: const Duration(minutes: 24),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: EpisodePickerScreen(content: content, onPlay: (_, _) async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تماشا کردی'), findsOneWidget);
    expect(find.text('تقریباً تماشا کردی'), findsOneWidget);
    final card = tester.widget<Material>(
      find.byKey(const Key('episode-card-logical:season-1-زیرنویس:episode-اول')),
    );
    expect(card.color, isNot(MovieColors.surface));
    final almostCard = tester.widget<Material>(
      find.byKey(const Key('episode-card-logical:season-1-زیرنویس:episode-دوم')),
    );
    expect(almostCard.color, isNot(MovieColors.surface));
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('one episode card selects quality without duplicating progress', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    MovieEpisode? played;
    await tester.pumpWidget(
      MaterialApp(
        home: EpisodePickerScreen(
          content: content,
          onPlay: (episode, _) async => played = episode,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('قسمت اول'), findsOneWidget);
    expect(find.text('قسمت دوم'), findsOneWidget);
    await tester.tap(find.byKey(const Key('quality-1080p')));
    await tester.pump();
    await tester.tap(find.text('پخش').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('پلیر داخلی (پیشنهادی)'));
    await tester.pumpAndSettle();
    expect(played?.fileUrl, 'https://example.com/1-1080.mkv');
  });

  testWidgets('phone transition defers the expensive episode grid', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: EpisodePickerScreen(
          content: content,
          deferInitialContent: true,
          onPlay: (_, _) async {},
        ),
      ),
    );

    expect(find.text(content.title), findsOneWidget);
    expect(find.text('قسمت اول'), findsNothing);
    await tester.pump(const Duration(milliseconds: 311));
    expect(find.text('قسمت اول'), findsOneWidget);
  });

  testWidgets('picker keeps the standard route back transition', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            key: const Key('open-picker'),
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => EpisodePickerScreen(
                  content: content,
                  deferInitialContent: true,
                  onPlay: (_, _) async {},
                ),
              ),
            ),
            child: const Text('باز کردن'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-picker')));
    await tester.pumpAndSettle();
    expect(find.text('انتخاب قسمت'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('انتخاب قسمت'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-picker')), findsOneWidget);
  });
}
