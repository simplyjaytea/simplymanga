import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/core/fold/fold_grid_delegate.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/modules/widgets/cover_grid_skeleton.dart';
import 'package:mangayomi/modules/widgets/gridview_widget.dart';

/// F-1 / D-6: the inner library grid is two pages — an even column count per
/// room with a gutter over the crease, so no cover is ever bisected. Cover
/// keeps the legacy width-derived grid untouched.
const _innerBand = Rect.fromLTRB(297, 0, 329, 890);
const _aspect = 0.69;

SliverConstraints _constraints(double width) => SliverConstraints(
  axisDirection: AxisDirection.down,
  growthDirection: GrowthDirection.forward,
  userScrollDirection: ScrollDirection.idle,
  scrollOffset: 0,
  precedingScrollExtent: 0,
  overlap: 0,
  remainingPaintExtent: 900,
  crossAxisExtent: width,
  crossAxisDirection: AxisDirection.right,
  viewportMainAxisExtent: 900,
  remainingCacheExtent: 1150,
  cacheOrigin: 0,
);

Widget _host(FoldStateDriver driver, Widget child) {
  return MaterialApp(
    home: Scaffold(body: FoldAwareShell(driver: driver, child: child)),
  );
}

Widget _grid({int itemCount = 40, ScrollController? controller, int? gridSize}) {
  return GridViewWidget(
    controller: controller,
    itemCount: itemCount,
    gridSize: gridSize,
    childAspectRatio: _aspect,
    itemBuilder: (context, index) =>
        ColoredBox(key: ValueKey('cell-$index'), color: Colors.black),
  );
}

/// Every built cell that is at least partly inside the viewport, in index
/// order. The first entry is the first-visible cover.
List<(int, Rect)> _visibleCells(WidgetTester tester, double viewportHeight) {
  final cells = <(int, Rect)>[];
  for (var i = 0; i < 80; i++) {
    final finder = find.byKey(ValueKey('cell-$i'));
    if (finder.evaluate().isEmpty) continue;
    final rect = tester.getRect(finder);
    if (rect.bottom > 0 && rect.top < viewportHeight) cells.add((i, rect));
  }
  cells.sort((a, b) => a.$1.compareTo(b.$1));
  return cells;
}

Future<void> _settleFold(
  WidgetTester tester,
  FakeFoldStateDriver driver,
  FoldState state,
  Size size,
) async {
  // Real folds arrive in two hops: the viewport resizes before the posture
  // settles. Pump the resize first so the anchor must survive both.
  tester.view.physicalSize = size;
  await tester.pump(const Duration(milliseconds: 1));
  driver.report(state);
  await tester.pump(const Duration(milliseconds: 1));
  // The scroll anchor lands in a post-frame callback after the re-column.
  await tester.pump();
}

void main() {
  group('FoldGridDelegate geometry', () {
    test('inner portrait: even columns, gutter over the crease, no bisect', () {
      const delegate = FoldGridDelegate(
        maxCrossAxisExtent: 220,
        childAspectRatio: _aspect,
        creaseBand: _innerBand,
      );
      final layout = delegate.geometryFor(626);
      expect(layout.columns, 4);
      expect(layout.columns.isEven, isTrue);
      // Two columns per room, rooms meeting the 32pt band with no overlap.
      for (var i = 0; i < layout.columns; i++) {
        final rect = layout.cellRect(i);
        expect(rect.overlaps(_innerBand), isFalse, reason: 'cell $i bisects');
        expect(rect.width / rect.height, closeTo(_aspect, 0.001));
      }
      expect(layout.cellRect(1).right, lessThanOrEqualTo(_innerBand.left));
      expect(layout.cellRect(2).left, greaterThanOrEqualTo(_innerBand.right));
      expect(layout.gutterEnd - layout.gutterStart, 32);
    });

    test('cover widths keep the legacy max-extent layout exactly', () {
      const delegate = FoldGridDelegate(
        maxCrossAxisExtent: 220,
        childAspectRatio: _aspect,
      );
      const legacy = SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        childAspectRatio: _aspect,
      );
      for (final width in [390.0, 466.0, 678.0]) {
        final mine = delegate.getLayout(_constraints(width));
        final theirs = legacy.getLayout(_constraints(width));
        for (var i = 0; i < 12; i++) {
          final a = mine.getGeometryForChildIndex(i);
          final b = theirs.getGeometryForChildIndex(i);
          expect(a.scrollOffset, b.scrollOffset, reason: 'width $width idx $i');
          expect(a.crossAxisOffset, b.crossAxisOffset);
          expect(a.mainAxisExtent, b.mainAxisExtent);
          expect(a.crossAxisExtent, b.crossAxisExtent);
        }
        expect(
          mine.computeMaxScrollOffset(40),
          theirs.computeMaxScrollOffset(40),
        );
      }
      // Cover landscape 678 stays on the legacy 4-column rule, no gutter.
      expect(delegate.geometryFor(678).columns, 4);
      expect(delegate.geometryFor(678).gutterEnd, 0);
    });

    test('fixed counts keep parity off-inner and turn even on inner', () {
      const off = FoldGridDelegate(
        fixedCrossAxisCount: 3,
        childAspectRatio: _aspect,
      );
      const legacy = SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: _aspect,
      );
      final a = off.getLayout(_constraints(390));
      final b = legacy.getLayout(_constraints(390));
      for (var i = 0; i < 9; i++) {
        expect(
          a.getGeometryForChildIndex(i).crossAxisOffset,
          b.getGeometryForChildIndex(i).crossAxisOffset,
        );
        expect(
          a.getGeometryForChildIndex(i).crossAxisExtent,
          b.getGeometryForChildIndex(i).crossAxisExtent,
        );
      }
      const on = FoldGridDelegate(
        fixedCrossAxisCount: 3,
        childAspectRatio: _aspect,
        creaseBand: _innerBand,
      );
      final inner = on.geometryFor(626);
      expect(inner.columns, 4);
      for (var i = 0; i < inner.columns; i++) {
        expect(inner.cellRect(i).overlaps(_innerBand), isFalse);
      }
    });

    test('inner landscape forces even columns without a vertical gutter', () {
      const delegate = FoldGridDelegate(
        maxCrossAxisExtent: 220,
        childAspectRatio: _aspect,
        forceEvenColumns: true,
      );
      final layout = delegate.geometryFor(890);
      expect(layout.columns.isEven, isTrue);
      expect(layout.gutterEnd, 0);
    });
  });

  group('library grid across the fold', () {
    testWidgets('inner portrait: no cover rect intersects the crease band', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(626, 890);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.innerPortrait);
      addTearDown(driver.dispose);

      await tester.pumpWidget(_host(driver, _grid()));
      await tester.pump();

      final cells = _visibleCells(tester, 890);
      expect(cells, isNotEmpty);
      for (final (index, rect) in cells) {
        expect(
          rect.overlaps(_innerBand),
          isFalse,
          reason: 'cover $index rides the spine: $rect',
        );
        expect(rect.width / rect.height, closeTo(_aspect, 0.001));
      }
      // Even column count: row one is four covers, two per room.
      final rowTop = cells.first.$2.top;
      final firstRow = cells.where((c) => c.$2.top == rowTop).toList();
      expect(firstRow.length, 4);
      expect(firstRow.length.isEven, isTrue);
    });

    testWidgets('cover keeps the legacy two-column grid, edge to edge', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);

      await tester.pumpWidget(_host(driver, _grid()));
      await tester.pump();

      final cells = _visibleCells(tester, 844);
      final rowTop = cells.first.$2.top;
      final firstRow = cells.where((c) => c.$2.top == rowTop).toList();
      expect(firstRow.length, 2);
      expect(firstRow[0].$2.left, 0);
      expect(firstRow[0].$2.width, 195);
      expect(firstRow[1].$2.left, 195);
    });

    testWidgets('cover landscape stays one room with the legacy grid', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(678, 466);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);

      await tester.pumpWidget(_host(driver, _grid()));
      await tester.pump();

      final spec = FoldLayoutScope.of(
        tester.element(find.byType(GridViewWidget)),
      );
      expect(spec.density, FoldDensity.compact);
      expect(spec.hasTwoRooms, isFalse);
      expect(spec.creaseBand, isNull);
      expect(spec.usesTwoPaneDetail, isFalse);

      final cells = _visibleCells(tester, 466);
      final rowTop = cells.first.$2.top;
      final firstRow = cells.where((c) => c.$2.top == rowTop).toList();
      // Legacy width rule: four flush columns, no fold gutter on the cover.
      expect(firstRow.length, 4);
      expect(firstRow[1].$2.left, firstRow[0].$2.right);
    });

    testWidgets('an odd user grid size still reads as two pages on inner', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(626, 890);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.innerPortrait);
      addTearDown(driver.dispose);

      await tester.pumpWidget(_host(driver, _grid(gridSize: 3)));
      await tester.pump();

      final cells = _visibleCells(tester, 890);
      for (final (index, rect) in cells) {
        expect(rect.overlaps(_innerBand), isFalse, reason: 'cover $index');
      }
      final rowTop = cells.first.$2.top;
      final firstRow = cells.where((c) => c.$2.top == rowTop).toList();
      expect(firstRow.length.isEven, isTrue);
    });

    testWidgets('the loading skeleton shares the crease-aware geometry', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(626, 890);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.innerPortrait);
      addTearDown(driver.dispose);

      await tester.pumpWidget(_host(driver, const CoverGridSkeleton()));
      await tester.pump();

      final grid = tester.widget<GridView>(find.byType(GridView));
      final delegate = grid.gridDelegate;
      expect(delegate, isA<FoldGridDelegate>());
      expect((delegate as FoldGridDelegate).creaseBand, isNotNull);
    });

    testWidgets(
      'cover->inner->cover keeps the first-visible cover under the thumb',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final driver = FakeFoldStateDriver(FoldState.cover);
        addTearDown(driver.dispose);
        final controller = ScrollController();
        addTearDown(controller.dispose);

        await tester.pumpWidget(_host(driver, _grid(controller: controller)));
        await tester.pump();

        // Mid-list: the first visible row is partly scrolled past the top.
        controller.jumpTo(600);
        await tester.pump();
        final before = _visibleCells(tester, 844).first;

        await _settleFold(
          tester,
          driver,
          FoldState.innerPortrait,
          const Size(626, 890),
        );
        final onInner = _visibleCells(tester, 890);
        expect(onInner, isNotEmpty);
        expect(
          onInner.first.$1,
          before.$1,
          reason: 'the first-visible cover changed across the fold',
        );
        expect(
          onInner.first.$2.top,
          closeTo(before.$2.top, 8),
          reason: 'the cover moved more than 8pt under the thumb',
        );
        for (final (_, rect) in onInner) {
          expect(rect.overlaps(_innerBand), isFalse);
          expect(rect.width / rect.height, closeTo(_aspect, 0.001));
        }

        await _settleFold(tester, driver, FoldState.cover, const Size(390, 844));
        final backOnCover = _visibleCells(tester, 844);
        expect(backOnCover.first.$1, before.$1);
        expect(backOnCover.first.$2.top, closeTo(before.$2.top, 8));
        expect(controller.offset, closeTo(600, 8));
      },
    );

    testWidgets('folding at the top keeps scroll offset within 8pt', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(driver, _grid(controller: controller)));
      await tester.pump();
      expect(controller.offset, 0);

      await _settleFold(
        tester,
        driver,
        FoldState.innerPortrait,
        const Size(626, 890),
      );
      expect(controller.offset, closeTo(0, 8));
      expect(_visibleCells(tester, 890).first.$1, 0);

      await _settleFold(tester, driver, FoldState.cover, const Size(390, 844));
      expect(controller.offset, closeTo(0, 8));
      expect(_visibleCells(tester, 844).first.$1, 0);
    });

    testWidgets(
      'the library path (primary scroll controller) keeps its place too',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final driver = FakeFoldStateDriver(FoldState.cover);
        addTearDown(driver.dispose);

        // No explicit controller: the grid rides the route's primary
        // controller, exactly like LibraryGridViewWidget.
        await tester.pumpWidget(_host(driver, _grid()));
        await tester.pump();
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        position.jumpTo(500);
        await tester.pump();
        final before = _visibleCells(tester, 844).first;

        await _settleFold(
          tester,
          driver,
          FoldState.innerPortrait,
          const Size(626, 890),
        );
        final after = _visibleCells(tester, 890);
        // The cover that was first visible stays under the thumb at the same
        // place. (With 2->4 columns its new row-mates may also peek in, so
        // the invariant is the anchored cover's position, not the min index.)
        final anchored = after.where((c) => c.$1 == before.$1).toList();
        expect(anchored, isNotEmpty, reason: 'first-visible cover lost');
        expect(anchored.first.$2.top, closeTo(before.$2.top, 8));
        for (final (_, rect) in after) {
          expect(rect.overlaps(_innerBand), isFalse);
        }

        // And folding back restores the exact cover-side scroll offset.
        await _settleFold(tester, driver, FoldState.cover, const Size(390, 844));
        final back = _visibleCells(tester, 844);
        expect(back.first.$1, before.$1);
        expect(back.first.$2.top, closeTo(before.$2.top, 8));
        expect(position.pixels, closeTo(500, 8));
      },
    );
  });
}