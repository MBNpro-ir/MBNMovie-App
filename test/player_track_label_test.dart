import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/core/player_track_label.dart';

void main() {
  test('media addresses and tickets never appear in track labels', () {
    const url = 'https://movie.mbnpro.ir/api/web/media?ticket=private-token';
    expect(playerTrackLabel(url, url, 'per'), 'فارسی');
    expect(playerTrackLabel(url, '', ''), 'ترک بدون نام');
    expect(playerTrackLabel('3', 'Original', 'eng'), 'Original · انگلیسی');
    expect(playerTrackLabel('1', null, null), 'ترک 1');
    expect(playerTrackLabel('no', url, 'per'), 'خاموش');
    expect(playerTrackLabel('auto', null, null), 'انتخاب خودکار');
  });
}
