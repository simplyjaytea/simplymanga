import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/core/fold/fold_transition.dart';
import 'package:material_ui/material_ui.dart';

/// C1 spec 6.2A: a settled-transition event. Exactly one [FoldTransition]
/// per settled change (previous != next), never on live metrics ticks.
/// previousSize = last live size under the old state; nextSize = last live
/// size reported in the settle frame. Completion is deferred to the end of
/// the post-frame report batch so nested shells sharing one controller
/// produce endpoints from a single viewport source (the innermost shell).
void main() {
  group('FoldStateController settled transitions', () {
    test('emits once per settled change, never on live size ticks', () async {
      final driver = FoldStateController(
        initialState: FoldState.cover,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(driver.dispose);
      final transitions = <FoldTransition>[];
      final sub = driver.transitions.transitions.listen(transitions.add);
      addTearDown(sub.cancel);

      // Live metrics ticks under the settled state: no transition.
      driver.reportSize(const Size(390, 844));
      driver.reportSize(const Size(392, 846));
      driver.reportSize(const Size(390, 844));
      driver.report(FoldState.cover); // same-state report: not a change
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(transitions, isEmpty);

      driver.report(FoldState.innerPortrait);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // The last live size reported in the settle frame completes the
      // transition (innermost shell wins in a nested topology).
      driver.reportSize(const Size(626, 890));
      driver.reportSize(const Size(628, 892)); // later ticks: no re-emit
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(transitions.length, 1);
      final t = transitions.single;
      expect(t.previous, FoldState.cover);
      expect(t.next, FoldState.innerPortrait);
      expect(t.previousSize, const Size(390, 844));
      expect(t.nextSize, const Size(628, 892));
      expect(driver.transitions.lastTransition, t);
    });

    test('previousSize is the LAST live size under the old state', () async {
      final driver = FoldStateController(
        initialState: FoldState.cover,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(driver.dispose);
      final transitions = <FoldTransition>[];
      final sub = driver.transitions.transitions.listen(transitions.add);
      addTearDown(sub.cancel);

      driver.reportSize(const Size(390, 844));
      driver.reportSize(const Size(410, 860)); // mid-fold live tick
      driver.report(FoldState.innerPortrait);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      driver.reportSize(const Size(626, 890));
      await Future<void>.delayed(Duration.zero); // flush stream delivery

      expect(transitions.single.previousSize, const Size(410, 860));
      expect(transitions.single.nextSize, const Size(626, 890));
    });

    test('rapid folds coalesce: latest state wins, one transition', () async {
      final driver = FoldStateController(
        initialState: FoldState.cover,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(driver.dispose);
      final transitions = <FoldTransition>[];
      final sub = driver.transitions.transitions.listen(transitions.add);
      addTearDown(sub.cancel);

      driver.reportSize(const Size(390, 844));
      driver.report(FoldState.innerPortrait);
      driver.report(FoldState.cover);
      driver.report(FoldState.innerLandscape);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      driver.reportSize(const Size(890, 626));
      await Future<void>.delayed(Duration.zero); // flush stream delivery

      expect(transitions.length, 1);
      expect(transitions.single.previous, FoldState.cover);
      expect(transitions.single.next, FoldState.innerLandscape);
      expect(transitions.single.nextSize, const Size(890, 626));
    });

    test('back-to-back settles without a live size report still emit once '
        'each', () async {
      final driver = FoldStateController(
        initialState: FoldState.cover,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(driver.dispose);
      final transitions = <FoldTransition>[];
      final sub = driver.transitions.transitions.listen(transitions.add);
      addTearDown(sub.cancel);

      driver.reportSize(const Size(390, 844));
      driver.report(FoldState.innerPortrait);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      driver.report(FoldState.innerLandscape);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      driver.reportSize(const Size(890, 626));
      await Future<void>.delayed(Duration.zero); // flush stream delivery

      expect(transitions.length, 2);
      expect(transitions[0].next, FoldState.innerPortrait);
      expect(transitions[1].previous, FoldState.innerPortrait);
      expect(transitions[1].next, FoldState.innerLandscape);
      expect(transitions[1].nextSize, const Size(890, 626));
    });

    test('B1 states stream is preserved alongside transitions', () async {
      final driver = FoldStateController(
        initialState: FoldState.cover,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(driver.dispose);
      final states = <FoldState>[];
      final sub = driver.states.listen(states.add);
      addTearDown(sub.cancel);

      driver.report(FoldState.innerPortrait);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(states, [FoldState.innerPortrait]);
      expect(driver.currentState, FoldState.innerPortrait);
    });
  });

  group('FoldAwareShell settled seam', () {
    testWidgets('onSettled fires once per settle with correct sizes; '
        'FakeFoldStateDriver is deterministic under pump()', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);
      final settled = <FoldTransition>[];

      await tester.pumpWidget(
        MaterialApp(
          home: FoldAwareShell(
            driver: driver,
            onSettled: settled.add,
            child: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      expect(settled, isEmpty);

      driver.report(FoldState.innerPortrait);
      tester.view.physicalSize = const Size(626, 890);
      // pump(1ms) fires the zero-debounce settle timer and rebuilds under
      // the new state AND size in one frame; the post-frame live-size
      // report then completes the transition. Deterministic, no wall clock.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();

      expect(settled.length, 1);
      expect(settled.single.previous, FoldState.cover);
      expect(settled.single.next, FoldState.innerPortrait);
      expect(settled.single.previousSize, const Size(390, 844));
      expect(settled.single.nextSize, const Size(626, 890));

      // Live size ticks without a settled change: no further transitions.
      tester.view.physicalSize = const Size(628, 892);
      await tester.pump();
      await tester.pump();
      expect(settled.length, 1);

      // Fold back: exactly one more transition.
      driver.report(FoldState.cover);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(settled.length, 2);
      expect(settled.last.previous, FoldState.innerPortrait);
      expect(settled.last.next, FoldState.cover);
      expect(settled.last.previousSize, const Size(628, 892));
      expect(settled.last.nextSize, const Size(390, 844));
    });

    testWidgets('nested shells sharing one controller: both endpoints come '
        'from the innermost viewport', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);
      final settled = <FoldTransition>[];

      // Production topology: root shell + reader shell mounted together,
      // one shared FoldStateController. The outer shell lays out first and
      // its post-frame size report registers first; the inner shell's
      // report must win so previousSize/nextSize share one source.
      await tester.pumpWidget(
        MaterialApp(
          home: FoldAwareShell(
            driver: driver,
            onSettled: settled.add,
            child: Center(
              child: SizedBox(
                width: 700,
                height: 500,
                child: FoldAwareShell(
                  driver: driver,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(settled, isEmpty);

      driver.report(FoldState.innerPortrait);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(settled.length, 1);
      expect(settled.single.previousSize, const Size(700, 500));
      expect(settled.single.nextSize, const Size(700, 500));

      // Fold back: the next transition's previousSize must still be the
      // innermost viewport, not the outer shell's size.
      driver.report(FoldState.cover);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(settled.length, 2);
      expect(settled.last.previousSize, const Size(700, 500));
      expect(settled.last.nextSize, const Size(700, 500));
    });

    testWidgets('FoldLayoutScope exposes the transition controller', (
      tester,
    ) async {
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);
      FoldTransitionController? seen;

      await tester.pumpWidget(
        MaterialApp(
          home: FoldAwareShell(
            driver: driver,
            child: Builder(
              builder: (context) {
                seen = FoldLayoutScope.maybeOf(context)?.transitions;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(seen, isNotNull);
      expect(seen, same(driver.transitions));
    });
  });
}
