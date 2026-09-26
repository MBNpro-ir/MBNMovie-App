import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/screens/detail_screen.dart';
import 'package:mbnmovie/services/movie_api.dart';

void main() {
  const groups = [
    CatalogGroup(id: '49', name: 'اکشن'),
    CatalogGroup(id: '50', name: 'کمدی'),
    CatalogGroup(id: '462', name: 'فیلم‌های ۲۰۲۴'),
  ];

  test('genre chip name resolves to the server group', () {
    expect(matchCatalogGroupByName(groups, 'اکشن')?.id, '49');
    expect(matchCatalogGroupByName(groups, '  اکشن  ')?.id, '49');
    expect(matchCatalogGroupByName(groups, 'فیلم‌های ۲۰۲۴')?.id, '462');
    // شامل: نام کوتاه داخل نام بلند.
    expect(matchCatalogGroupByName(groups, 'فیلم')?.id, '462');
  });

  test('unknown or empty genre resolves to null', () {
    expect(matchCatalogGroupByName(groups, 'ژانر ناموجود'), isNull);
    expect(matchCatalogGroupByName(groups, '  '), isNull);
    expect(matchCatalogGroupByName(const [], 'اکشن'), isNull);
  });
}
