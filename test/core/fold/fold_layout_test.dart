import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';

void main() {
  group('FoldLayoutSpec', () {
    test('cover landscape stays compact and never creates a second room', () {
      final spec = FoldLayoutSpec.resolve(
        foldState: FoldState.cover,
        size: const Size(678, 466),
      );

      expect(spec.density, FoldDensity.compact);
      expect(spec.hasTwoRooms, isFalse);
      expect(spec.creaseBand, isNull);
      expect(spec.usesTwoPaneDetail, isFalse);
    });

    test('inner portrait centers a 32 point vertical crease band', () {
      final spec = FoldLayoutSpec.resolve(
        foldState: FoldState.innerPortrait,
        size: const Size(626, 890),
      );

      expect(spec.density, FoldDensity.inner);
      expect(spec.hasTwoRooms, isTrue);
      expect(spec.creaseBand, const Rect.fromLTRB(297, 0, 329, 890));
    });

    test('inner landscape centers a horizontal crease band', () {
      final spec = FoldLayoutSpec.resolve(
        foldState: FoldState.innerLandscape,
        size: const Size(890, 626),
      );

      expect(spec.creaseBand, const Rect.fromLTRB(0, 297, 890, 329));
      expect(spec.controlsRegion, const Rect.fromLTRB(0, 345, 890, 626));
    });

    test('unknown posture does not invent a crease or second room', () {
      final spec = FoldLayoutSpec.resolve(
        foldState: FoldState.unknown,
        size: const Size(890, 626),
      );

      expect(spec.hasTwoRooms, isFalse);
      expect(spec.creaseBand, isNull);
      expect(spec.usesTwoPaneDetail, isTrue);
    });
  });

  testWidgets('inner detail rooms clear crease and preserve outer margins', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(626, 890);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final driver = FakeFoldStateDriver(FoldState.innerPortrait);
    addTearDown(driver.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoldAwareShell(
            driver: driver,
            child: const FoldTwoRoomLayout(
              firstRoom: SizedBox.expand(key: ValueKey('first-room')),
              secondRoom: SizedBox.expand(key: ValueKey('second-room')),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(const ValueKey('first-room'))),
      const Rect.fromLTRB(16, 16, 281, 874),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('second-room'))),
      const Rect.fromLTRB(345, 16, 610, 874),
    );
  });

  test(
    'settled fold driver coalesces bursts and emits only the latest state',
    () async {
      final driver = FoldStateController(
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(driver.dispose);
      final states = <FoldState>[];
      final subscription = driver.states.listen(states.add);
      addTearDown(subscription.cancel);

      driver.report(FoldState.innerPortrait);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      driver.report(FoldState.cover);
      driver.report(FoldState.innerLandscape);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(states, [FoldState.innerLandscape]);
    },
  );

  testWidgets('fold changes preserve the mounted child and its local state', (
    tester,
  ) async {
    final driver = FakeFoldStateDriver(FoldState.cover);
    addTearDown(driver.dispose);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoldAwareShell(
            driver: driver,
            child: _StatefulProbe(onBuild: () => builds++),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('increment')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    final initialBuilds = builds;
    driver.report(FoldState.innerPortrait);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('1'), findsOneWidget);
    expect(find.text('innerPortrait'), findsOneWidget);
    expect(builds, greaterThan(initialBuilds));
  });
}

class _StatefulProbe extends StatefulWidget {
  const _StatefulProbe({required this.onBuild});

  final VoidCallback onBuild;

  @override
  State<_StatefulProbe> createState() => _StatefulProbeState();
}

class _StatefulProbeState extends State<_StatefulProbe> {
  int count = 0;

  @override
  Widget build(BuildContext context) {
    widget.onBuild();
    return Column(
      children: [
        Text(FoldLayoutScope.of(context).foldState.name),
        Text('$count'),
        GestureDetector(
          key: const ValueKey('increment'),
          onTap: () => setState(() => count++),
          child: const Text('increment'),
        ),
      ],
    );
  }
}
