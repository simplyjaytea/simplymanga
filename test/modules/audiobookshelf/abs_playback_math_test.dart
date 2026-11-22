import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/modules/audiobookshelf/abs_playback_math.dart';

void main() {
  const chapter = Duration(minutes: 20);

  test('locates a position inside a track', () {
    final located = locatePosition([
      chapter,
      chapter,
      chapter,
    ], const Duration(minutes: 30));

    expect(located.index, 1);
    expect(located.offset, const Duration(minutes: 10));
  });

  test('clamps past the end to the last track', () {
    final located = locatePosition([
      chapter,
      chapter,
    ], const Duration(hours: 2));

    expect(located.index, 1);
    expect(located.offset, chapter);
  });

  test('an empty book starts at zero in the first track', () {
    final located = locatePosition([], const Duration(minutes: 5));

    expect(located.index, 0);
    expect(located.offset, Duration.zero);
  });

  test('files with no known duration start at the first track', () {
    final located = locatePosition([
      Duration.zero,
      Duration.zero,
    ], const Duration(minutes: 5));

    expect(located.index, 0);
    expect(located.offset, Duration.zero);
  });

  test('a track position maps back to the book position', () {
    expect(
      absolutePosition(
        [chapter, chapter, chapter],
        2,
        const Duration(minutes: 5),
      ),
      const Duration(minutes: 45),
    );
  });

  test('absolutePosition clamps a bad track index', () {
    expect(
      absolutePosition([chapter], 9, const Duration(minutes: 1)),
      const Duration(minutes: 1),
    );
  });
}
