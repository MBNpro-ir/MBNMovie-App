import 'package:flutter_test/flutter_test.dart';
import 'package:mbnmovie/widgets/content_art.dart';

void main() {
  test('portrait selection prefers a vertical decoded image', () {
    expect(
      artworkAspectScore(.67, ArtworkOrientation.portrait),
      greaterThan(artworkAspectScore(1.78, ArtworkOrientation.portrait)),
    );
  });

  test('landscape selection prefers a wide decoded image', () {
    expect(
      artworkAspectScore(1.78, ArtworkOrientation.landscape),
      greaterThan(artworkAspectScore(.67, ArtworkOrientation.landscape)),
    );
  });
}
