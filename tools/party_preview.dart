// Isolated synthetic entrypoint. Never use as a release target.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:mbn_party/mbn_party.dart';
import 'package:mbnmovie/core/app_platform.dart';
import 'package:mbnmovie/core/theme.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:mbnmovie/services/app_party.dart';
import 'package:mbnmovie/services/mbn_auth.dart';
import 'package:mbnmovie/services/mbn_sync.dart';
import 'package:mbnmovie/services/movie_api.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'party_preview_store.dart';

const _base = 'http://127.0.0.1:18641';
const _app = 'movie';
const _user = String.fromEnvironment('PREVIEW_USER', defaultValue: '1');
MovieContent get fixture => MovieContent(
  id: 'preview-film',
  title: 'آزمایش تماشای گروهی',
  subtitle: 'پیش‌نمایش محلی',
  description: '',
  year: 2026,
  rating: 0,
  kind: ContentKind.movie,
  colors: const [Color(0xFF172235), Color(0xFF0D1422)],
  genres: const [],
  seasons: [
    MovieSeason(
      id: 'preview-season',
      name: 'فیلم',
      episodes: [
        MovieEpisode(
          id: 'preview-ep',
          name: 'قسمت آزمایشی · 720p',
          fileUrl: kIsWeb
              ? '/preview/media/clip.mp4'
              : '$_base/preview/media/clip.mp4',
        ),
      ],
    ),
  ],
);

class _Catalog implements ContentApi {
  @override
  Future<MovieContent> details(MovieContent summary) async => fixture;
  @override
  Future<List<MovieComment>> comments(String id) async => [];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await isolatePreviewPreferences(_user);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('player_gestures_introduced', true);
  final user = kIsWeb
      ? Uri.base.queryParameters['user'] ?? _user
      : Platform.environment['MBN_PREVIEW_USER'] ?? _user;
  final response = await http.get(
    Uri.parse('$_base/preview/identity?app=$_app&user=$user'),
  );
  final data = jsonDecode(response.body) as Map;
  final auth = MbnAuth(baseUrl: _base)..token = data['token'].toString();
  MbnSync.instance.configure(auth: auth);
  AppParty.bind(_Catalog());
  await PartyHub.instance.client!.refresh();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('MBNMovie Party Preview · User $user');
    await windowManager.setSize(const Size(1200, 800));
    await windowManager.show();
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MovieTheme.dark,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Preview(),
    ),
  );
}

class _Preview extends StatelessWidget {
  const _Preview();
  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    appBar: AppBar(
      leadingWidth: 100,
      leading: Builder(
        builder: (ctx) => Row(
          children: [
            IconButton(
              onPressed: () => Scaffold.of(ctx).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
            const PartyButton(),
          ],
        ),
      ),
      title: const Text('MBNMovie · پیش‌نمایش پارتی'),
    ),
    drawer: const Drawer(child: Center(child: Text('محیط آزمایشی محلی'))),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.diversity_2_rounded,
                size: 72,
                color: Color(0xFF83E9C5),
              ),
              const SizedBox(height: 20),
              const Text(
                'پارتی · با هم تماشا می‌کنیم',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'این پیش‌نمایش با حساب‌ها و ویدیوی آزمایشی روی همین سیستم اجرا می‌شود.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => openParty(context),
                icon: const Icon(Icons.chat_rounded),
                label: const Text('دوستان و گفت‌وگوها'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => AppParty.send(context, fixture),
                icon: const Icon(Icons.send_rounded),
                label: const Text('ارسال فیلم و دعوت به تماشا'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlayerScreen(
                      content: fixture,
                      episode: fixture.seasons.first.episodes.first,
                    ),
                  ),
                ),
                icon: const Icon(Icons.movie_rounded),
                label: const Text('پلیر · تست رهاکردن صدا و زیرنویس'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
