import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

class _Paths extends PathProviderWindows {
  _Paths(this.path);
  final String path;
  bool failNext = false;
  @override
  Future<String?> getApplicationSupportPath() async {
    if (failNext) {
      failNext = false;
      throw FileSystemException('QA write failure');
    }
    return path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'concurrent disk writes retain all keys, ordering, removes and clear',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'mbn-preferences-test-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final store = SharedPreferencesWindows()
        ..pathProvider = _Paths(temp.path);
      await store.getAll();
      expect(
        await store.setValue('String', 'flutter.history', 'x' * 1024 * 1024),
        true,
      );
      expect(
        await Future.wait([
          for (var i = 0; i < 20; i++)
            store.setValue('int', 'flutter.pos_$i', i),
          store.setValue('String', 'flutter.same', 'older'),
          store.setValue('String', 'flutter.same', 'newer'),
        ]),
        everyElement(true),
      );
      final file = File('${temp.path}/shared_preferences.json');
      var data = jsonDecode(await file.readAsString()) as Map;
      for (var i = 0; i < 20; i++) {
        expect(data['flutter.pos_$i'], i);
      }
      expect(data['flutter.same'], 'newer');
      await store.remove('flutter.same');
      final reopened = SharedPreferencesWindows()
        ..pathProvider = _Paths(temp.path);
      expect((await reopened.getAll()).containsKey('flutter.same'), false);
      await store.setValue('String', 'other.keep', 'keep');
      await store.clear();
      data = jsonDecode(await file.readAsString()) as Map;
      expect(data, {'other.keep': 'keep'});
    },
  );

  test('failed persistence does not block later writes', () async {
    final temp = await Directory.systemTemp.createTemp('mbn-preferences-test-');
    addTearDown(() => temp.delete(recursive: true));
    final paths = _Paths(temp.path);
    final store = SharedPreferencesWindows()..pathProvider = paths;
    await store.getAll();
    paths.failNext = true;
    expect(await store.setValue('int', 'flutter.pos', 1), false);
    expect(await store.setValue('int', 'flutter.pos', 2), true);
    expect(
      (await (SharedPreferencesWindows()..pathProvider = paths)
          .getAll())['flutter.pos'],
      2,
    );
  });
}
