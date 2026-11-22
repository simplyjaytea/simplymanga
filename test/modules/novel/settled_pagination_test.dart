import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/modules/novel/utils/settled_pagination.dart';

void main() {
  testWidgets('pagination runs once when posture settles, not per frame', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    final cache = SettledPosturePagination<int>();
    var calls = 0;

    Future<void> rebuild(FoldState posture, double width) async {
      cache.resolve(
        posture: posture,
        options: 'chapter-1-font-14',
        paginate: () {
          calls++;
          return width.round();
        },
      );
    }

    await rebuild(driver.currentState, 390);
    await rebuild(driver.currentState, 420);
    expect(calls, 1);

    driver.report(FoldState.innerPortrait);
    await tester.pump(const Duration(milliseconds: 1));
    await rebuild(driver.currentState, 626);
    expect(calls, 2);

    // Metrics can change repeatedly before the settled posture changes.
    await rebuild(driver.currentState, 610);
    await rebuild(driver.currentState, 626);
    expect(calls, 2);

    driver.report(FoldState.cover);
    await tester.pump(const Duration(milliseconds: 1));
    await rebuild(driver.currentState, 390);
    expect(calls, 3);
  });

  test('formatting changes invalidate a settled pagination', () {
    final cache = SettledPosturePagination<String>();
    var calls = 0;

    String paginate() => 'page-${++calls}';

    expect(
      cache.resolve(
        posture: FoldState.cover,
        options: (fontSize: 14, theme: 'dark'),
        paginate: paginate,
      ),
      'page-1',
    );
    expect(
      cache.resolve(
        posture: FoldState.cover,
        options: (fontSize: 16, theme: 'dark'),
        paginate: paginate,
      ),
      'page-2',
    );
    expect(calls, 2);
  });
}
