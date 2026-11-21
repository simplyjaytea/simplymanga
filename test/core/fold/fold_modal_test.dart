import 'package:flutter/scheduler.dart'
    show Ticker, TickerCallback, TickerProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/core/fold/fold_modal.dart';
import 'package:mangayomi/modules/widgets/custom_draggable_tabbar.dart';
import 'package:shiori/shiori.dart';

/// F-2 / AC-10: an open sheet or dialog stays open across a settled fold,
/// re-presents in the surviving room, clears the crease band, and keeps its
/// scroll, field state and focus. The routed branch underneath never remounts.
const _cover = Size(390, 844);
const _innerPortrait = Size(626, 890);
const _innerLandscape = Size(890, 626);
const _coverLandscape = Size(678, 466);

const _portraitBand = Rect.fromLTRB(297, 0, 329, 890);
const _landscapeBand = Rect.fromLTRB(0, 297, 890, 329);
const _leftRoom = Rect.fromLTRB(16, 16, 281, 874);
const _rightRoom = Rect.fromLTRB(345, 16, 610, 874);
const _lowerRoom = Rect.fromLTRB(16, 345, 874, 610);

void _surface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

bool _intersects(Rect a, Rect b) =>
    a.left < b.right && b.left < a.right && a.top < b.bottom && b.top < a.bottom;

void _expectClears(Rect rect, Rect band) {
  expect(
    _intersects(rect, band),
    isFalse,
    reason: '$rect renders across the crease band $band',
  );
}

void _expectInside(Rect rect, Rect room) {
  expect(rect.left, greaterThanOrEqualTo(room.left - 0.5), reason: '$rect');
  expect(rect.top, greaterThanOrEqualTo(room.top - 0.5), reason: '$rect');
  expect(rect.right, lessThanOrEqualTo(room.right + 0.5), reason: '$rect');
  expect(rect.bottom, lessThanOrEqualTo(room.bottom + 0.5), reason: '$rect');
}

Widget _harness(
  FoldStateDriver driver,
  Widget child, {
  bool foldScope = true,
}) => MaterialApp(
  builder: foldScope
      ? (context, nav) => FoldOverlayScope(driver: driver, child: nav!)
      : null,
  home: Scaffold(body: FoldAwareShell(driver: driver, child: child)),
);

/// Reports a posture and pumps past the settle window. Works for both the
/// zero-debounce fake and the real 120 ms controller.
Future<void> _fold(
  WidgetTester tester,
  FoldStateController driver,
  FoldState state,
  Size size,
) async {
  tester.view.physicalSize = size;
  driver.report(state);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Finder _sheetSurface() => find
    .ancestor(of: find.byType(ShioriSheet), matching: find.byType(Material))
    .first;

Finder _dialogCard() => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(Material))
    .first;

class _BranchProbe extends StatefulWidget {
  const _BranchProbe({required this.onInit, required this.onOpen});
  final VoidCallback onInit;
  final void Function(BuildContext context) onOpen;

  @override
  State<_BranchProbe> createState() => _BranchProbeState();
}

class _BranchProbeState extends State<_BranchProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => widget.onOpen(context),
      child: const Text('open sheet'),
    ),
  );
}

/// Sheet content with a counter, a bump button and a scrollable list: the
/// state AC-10 must keep across a fold.
class _SheetProbe extends StatefulWidget {
  const _SheetProbe({required this.controller});
  final ScrollController controller;

  @override
  State<_SheetProbe> createState() => _SheetProbeState();
}

class _SheetProbeState extends State<_SheetProbe> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Text('count: $count'),
          TextButton(
            onPressed: () => setState(() => count++),
            child: const Text('bump'),
          ),
        ],
      ),
      Expanded(
        child: ListView.builder(
          controller: widget.controller,
          itemCount: 60,
          itemExtent: 40,
          itemBuilder: (_, i) => Text('item $i'),
        ),
      ),
    ],
  );
}

class _TestVsync implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

void main() {
  group('foldOverlayRooms', () {
    test('inner portrait rooms mirror the two-room layout law', () {
      final spec = FoldLayoutSpec.resolve(
        foldState: FoldState.innerPortrait,
        size: _innerPortrait,
      );
      final rooms = foldOverlayRooms(spec, _innerPortrait)!;
      expect(rooms.creaseBand, _portraitBand);
      expect(rooms.leftRoom, _leftRoom);
      expect(rooms.rightRoom, _rightRoom);
      expect(rooms.lowerRoom, isNull);
    });

    test('inner landscape docks overlays below the horizontal crease', () {
      final spec = FoldLayoutSpec.resolve(
        foldState: FoldState.innerLandscape,
        size: _innerLandscape,
      );
      final rooms = foldOverlayRooms(spec, _innerLandscape)!;
      expect(rooms.creaseBand, _landscapeBand);
      expect(rooms.lowerRoom, _lowerRoom);
      expect(rooms.leftRoom, isNull);
      expect(rooms.rightRoom, isNull);
    });

    test('cover postures have no rooms', () {
      for (final state in [FoldState.cover, FoldState.unknown]) {
        final spec = FoldLayoutSpec.resolve(
          foldState: state,
          size: _cover,
        );
        expect(foldOverlayRooms(spec, _cover), isNull);
      }
      final landscape = FoldLayoutSpec.resolve(
        foldState: FoldState.cover,
        size: _coverLandscape,
      );
      expect(foldOverlayRooms(landscape, _coverLandscape), isNull);
    });
  });

  testWidgets(
    'sheet opened on cover re-presents in the right room on inner portrait',
    (tester) async {
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);
      _surface(tester, _cover);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          driver,
          _BranchProbe(
            onInit: () {},
            onOpen: (context) => showShioriSheet<void>(
              context,
              title: 'Filter',
              builder: (_) => _SheetProbe(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();

      final coverRect = tester.getRect(_sheetSurface());
      expect(coverRect.width, closeTo(_cover.width, 0.5));
      expect(coverRect.bottom, closeTo(_cover.height, 0.5));

      await _fold(tester, driver, FoldState.innerPortrait, _innerPortrait);

      expect(find.byType(ShioriSheet), findsOneWidget);
      final innerRect = tester.getRect(_sheetSurface());
      _expectInside(innerRect, _rightRoom);
      _expectClears(innerRect, _portraitBand);
      expect(innerRect.bottom, closeTo(_rightRoom.bottom, 0.5));
    },
  );

  testWidgets('sheet scroll offset and state survive cover→inner→cover', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) => showShioriSheet<void>(
            context,
            title: 'Filter',
            builder: (_) => _SheetProbe(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    controller.jumpTo(200);
    await tester.pump();
    await tester.tap(find.text('bump'));
    await tester.tap(find.text('bump'));
    await tester.pump();
    expect(find.text('count: 2'), findsOneWidget);
    final stateBefore = tester.state<_SheetProbeState>(
      find.byType(_SheetProbe),
    );

    await _fold(tester, driver, FoldState.innerPortrait, _innerPortrait);
    await _fold(tester, driver, FoldState.cover, _cover);

    expect(
      tester.state<_SheetProbeState>(find.byType(_SheetProbe)),
      same(stateBefore),
    );
    expect(find.text('count: 2'), findsOneWidget);
    expect(controller.offset, closeTo(200, 8));
    // Offset 200 with 40pt items: item 5 is the first visible row.
    expect(find.text('item 5'), findsOneWidget);
  });

  testWidgets(
    'stale rooms never squeeze the sheet during the settle window',
    (tester) async {
      // Real 120 ms debounce: the display folds to cover immediately, the
      // settled posture (and the new rooms) arrives one window later. The
      // old inner rooms must never be applied to the cover display.
      final driver = FoldStateController(initialState: FoldState.innerPortrait);
      addTearDown(driver.dispose);
      _surface(tester, _innerPortrait);
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _harness(
          driver,
          _BranchProbe(
            onInit: () {},
            onOpen: (context) => showShioriSheet<void>(
              context,
              title: 'Filter',
              builder: (_) => _SheetProbe(controller: controller),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open sheet'));
      await tester.pumpAndSettle();
      expect(tester.getRect(_sheetSurface()).width, closeTo(265, 0.5));

      tester.view.physicalSize = _cover;
      driver.report(FoldState.cover);
      await tester.pump();
      expect(
        tester.getRect(_sheetSurface()).width,
        closeTo(390, 0.5),
        reason: 'stale inner rooms squeezed the sheet on the cover display',
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getRect(_sheetSurface()).width, closeTo(390, 0.5));
      expect(find.text('count: 0'), findsOneWidget);
    },
  );

  testWidgets(
    'sheet invoked from the left room returns to the left room after a fold',
    (tester) async {
      final driver = FakeFoldStateDriver(FoldState.innerPortrait);
      addTearDown(driver.dispose);
      _surface(tester, _innerPortrait);

      Widget openButton(String label, Alignment alignment) => Align(
        alignment: alignment,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => showShioriSheet<void>(
              context,
              title: label,
              builder: (_) => const SizedBox(height: 150, child: Text('body')),
            ),
            child: Text(label),
          ),
        ),
      );

      await tester.pumpWidget(
        _harness(
          driver,
          Stack(
            children: [
              openButton('left', Alignment.centerLeft),
              openButton('right', Alignment.centerRight),
            ],
          ),
        ),
      );
      await tester.tap(find.text('left'));
      await tester.pumpAndSettle();

      final leftRect = tester.getRect(_sheetSurface());
      _expectInside(leftRect, _leftRoom);
      _expectClears(leftRect, _portraitBand);

      await _fold(tester, driver, FoldState.cover, _cover);
      expect(
        tester.getRect(_sheetSurface()).width,
        closeTo(_cover.width, 0.5),
      );

      await _fold(tester, driver, FoldState.innerPortrait, _innerPortrait);
      final backRect = tester.getRect(_sheetSurface());
      _expectInside(backRect, _leftRoom);
      _expectClears(backRect, _portraitBand);
    },
  );

  testWidgets('sheet sits below the horizontal crease on inner landscape', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) => showShioriSheet<void>(
            context,
            title: 'Filter',
            builder: (_) => _SheetProbe(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    await _fold(tester, driver, FoldState.innerLandscape, _innerLandscape);

    final rect = tester.getRect(_sheetSurface());
    _expectInside(rect, _lowerRoom);
    _expectClears(rect, _landscapeBand);
    expect(rect.top, greaterThanOrEqualTo(_landscapeBand.bottom));
  });

  testWidgets('cover landscape keeps a single-room sheet', (tester) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) => showShioriSheet<void>(
            context,
            title: 'Filter',
            builder: (_) => _SheetProbe(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    await _fold(tester, driver, FoldState.cover, _coverLandscape);

    final rect = tester.getRect(_sheetSurface());
    expect(rect.width, closeTo(_coverLandscape.width, 0.5));
    expect(rect.bottom, closeTo(_coverLandscape.height, 0.5));
  });

  testWidgets('dialog re-presents in the room and still resolves', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);
    bool? result;

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) async {
            result = await showShioriConfirm(
              context,
              title: 'Delete downloads?',
              message: '12 chapters will be removed from this device.',
              confirmLabel: 'Delete',
              destructive: true,
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Delete downloads?'), findsOneWidget);

    await _fold(tester, driver, FoldState.innerPortrait, _innerPortrait);

    expect(find.text('Delete downloads?'), findsOneWidget);
    final rect = tester.getRect(_dialogCard());
    _expectInside(rect, _rightRoom);
    _expectClears(rect, _portraitBand);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('prompt keeps field text and focus across folds', (tester) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);
    String? result;

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) async {
            result = await showShioriPrompt(
              context,
              title: 'Rename',
              confirmLabel: 'Save',
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    final focusBefore = FocusManager.instance.primaryFocus;
    expect(focusBefore, isNotNull);

    await _fold(tester, driver, FoldState.innerPortrait, _innerPortrait);
    await _fold(tester, driver, FoldState.cover, _cover);
    await _fold(tester, driver, FoldState.innerPortrait, _innerPortrait);

    expect(FocusManager.instance.primaryFocus, same(focusBefore));
    expect(find.text('hello'), findsOneWidget);
    final rect = tester.getRect(_dialogCard());
    _expectInside(rect, _rightRoom);
    _expectClears(rect, _portraitBand);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, 'hello');
  });

  testWidgets('routed branch is not remounted across folds with a sheet open', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);
    var branchInits = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () => branchInits++,
          onOpen: (context) => showShioriSheet<void>(
            context,
            title: 'Filter',
            builder: (_) => _SheetProbe(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    final branchBefore = tester.state<_BranchProbeState>(
      find.byType(_BranchProbe),
    );
    expect(branchInits, 1);

    await _fold(tester, driver, FoldState.innerPortrait, _innerPortrait);
    await _fold(tester, driver, FoldState.cover, _cover);

    expect(branchInits, 1);
    expect(
      tester.state<_BranchProbeState>(find.byType(_BranchProbe)),
      same(branchBefore),
    );
    expect(
      find.byKey(const ValueKey('fold-aware-routed-content')),
      findsOneWidget,
    );
    expect(find.byType(ShioriSheet), findsOneWidget);
  });

  testWidgets('re-presentation waits for the settled posture (120 ms)', (
    tester,
  ) async {
    final driver = FoldStateController(initialState: FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) => showShioriSheet<void>(
            context,
            title: 'Filter',
            builder: (_) => _SheetProbe(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = _innerPortrait;
    driver.report(FoldState.innerPortrait);
    await tester.pump(const Duration(milliseconds: 50));

    // Mid-debounce: the sheet still spans the display, not yet room-placed.
    final midRect = tester.getRect(_sheetSurface());
    expect(midRect.left, lessThan(_portraitBand.left));

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    final settledRect = tester.getRect(_sheetSurface());
    _expectInside(settledRect, _rightRoom);
    _expectClears(settledRect, _portraitBand);
  });

  testWidgets('rapid fidgeting lands on the final posture with state intact', (
    tester,
  ) async {
    final driver = FoldStateController(initialState: FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    var settles = 0;
    final sub = driver.states.listen((_) => settles++);
    addTearDown(sub.cancel);

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) => showShioriSheet<void>(
            context,
            title: 'Filter',
            builder: (_) => _SheetProbe(controller: controller),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bump'));
    await tester.pump();
    final stateBefore = tester.state<_SheetProbeState>(
      find.byType(_SheetProbe),
    );

    tester.view.physicalSize = _innerPortrait;
    driver.report(FoldState.innerPortrait);
    driver.report(FoldState.cover);
    driver.report(FoldState.innerPortrait);
    driver.report(FoldState.cover);
    driver.report(FoldState.innerPortrait);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(settles, 1);
    expect(driver.currentState, FoldState.innerPortrait);
    final rect = tester.getRect(_sheetSurface());
    _expectInside(rect, _rightRoom);
    _expectClears(rect, _portraitBand);
    expect(
      tester.state<_SheetProbeState>(find.byType(_SheetProbe)),
      same(stateBefore),
    );
    expect(find.text('count: 1'), findsOneWidget);
  });

  testWidgets('without the overlay scope the sheet keeps classic geometry', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.innerPortrait);
    addTearDown(driver.dispose);
    _surface(tester, _innerPortrait);

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) => showShioriSheet<void>(
            context,
            title: 'Filter',
            builder: (_) => const SizedBox(height: 150, child: Text('body')),
          ),
        ),
        foldScope: false,
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    final rect = tester.getRect(_sheetSurface());
    expect(rect.width, closeTo(_innerPortrait.width, 0.5));
    expect(rect.bottom, closeTo(_innerPortrait.height, 0.5));
  });

  testWidgets('customDraggableTabBar re-presents in the room, keeps its tab', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    _surface(tester, _cover);

    await tester.pumpWidget(
      _harness(
        driver,
        _BranchProbe(
          onInit: () {},
          onOpen: (context) => customDraggableTabBar(
            context: context,
            vsync: _TestVsync(),
            tabs: const [Tab(text: 'One'), Tab(text: 'Two')],
            children: const [
              SizedBox(height: 150, child: Text('tab one')),
              SizedBox(height: 150, child: Text('tab two')),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
      1,
    );

    await _fold(tester, driver, FoldState.innerPortrait, _innerPortrait);

    final ground = find
        .ancestor(
          of: find.byType(TabBar),
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final rect = tester.getRect(ground);
    _expectInside(rect, _rightRoom);
    _expectClears(rect, _portraitBand);
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
      1,
    );

    await _fold(tester, driver, FoldState.cover, _cover);
    expect(
      tester.widget<TabBar>(find.byType(TabBar)).controller!.index,
      1,
    );
    expect(find.text('tab two'), findsOneWidget);
  });
}
