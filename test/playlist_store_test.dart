import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/playlist_store.dart';
import 'package:mbnmovie/models/movie_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

MovieContent _item(String id, String title) => MovieContent(
  id: id,
  title: title,
  subtitle: 'فیلم',
  description: '',
  year: 2026,
  rating: 7.5,
  kind: ContentKind.movie,
  colors: const [Color(0xFF4665B3), Color(0xFF10182B)],
  genres: const ['درام'],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('playlists can be created, filled, renamed and deleted', () async {
    final store = PlaylistStore();
    expect(await store.playlists(), isEmpty);

    final first = await store.create('شب‌های فیلم');
    final second = await store.create('سریال‌های آخر هفته');
    expect((await store.playlists()).length, 2);

    expect(await store.addTitle(first.id, _item('1', 'فیلم نمونه')), isTrue);
    // Adding the same title twice does not duplicate it.
    expect(await store.addTitle(first.id, _item('1', 'فیلم نمونه')), isFalse);
    expect(await store.addTitle(first.id, _item('2', 'سریال نمونه')), isTrue);

    final containing = await store.listIdsContaining('1');
    expect(containing, {first.id});

    await store.rename(second.id, 'نام تازه');
    final renamed =
        (await store.playlists()).firstWhere((list) => list.id == second.id);
    expect(renamed.name, 'نام تازه');

    expect(await store.removeTitle(first.id, '1'), isTrue);
    final remaining =
        (await store.playlists()).firstWhere((list) => list.id == first.id);
    expect(remaining.items.map((item) => item.id), ['2']);

    await store.delete(first.id);
    await store.delete(second.id);
    expect(await store.playlists(), isEmpty);
  });
}
