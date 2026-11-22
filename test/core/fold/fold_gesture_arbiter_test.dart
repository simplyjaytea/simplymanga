import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/core/fold/fold_gesture_arbiter.dart';
import 'package:mangayomi/core/fold/fold_gesture_boundary.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/core/fold/fold_transition.dart';
import 'package:material_ui/material_ui.dart';

/// C1 spec 5.3: the fold boundary arbitration invariants.
/// - No double-fire: one fold -> at most one anchor restore, one page change.
/// - No velocity carry: a fling at fold becomes a stop, not a slide.
/// - No pointer leak: active-pointer count returns to zero.
/// - cancelInFlight(keepAnchor) freezes at the anchor; a fresh drag works.
void main() {
  const coverSize = Size(390, 844);
  const innerSize = Size(626, 890);

  FoldTransition settle({
    FoldState previous = FoldState.cover,
    FoldState next = FoldState.innerPortrait,
  }) => FoldTransition(
    previous: previous,
    next: next,
    previousSize: coverSize,
    nextSize: innerSize,
    settledAt: DateTime.now(),
  );

  /// A manual post-frame queue so the pure tests stay binding-free and
  /// deterministic: nothing runs until the test flushes the frame seam.
  ({DefaultFoldGestureArbiter arbiter, void Function() flush}) harness({
    List<String>? log,
  }) {
    final queue = <void Function()>[];
    final events = log ?? <String>[];
    final arbiter = DefaultFoldGestureArbiter(
      stopActivity: () => events.add('stop'),
      commitAnchor: () => events.add('commit'),
      restoreAnchor: () => events.add('restore'),
      postFrameScheduler: queue.add,
    );
    return (arbiter: arbiter, flush: () {
      final pending = List.of(queue);
      queue.clear();
      for (final cb in pending) {
        cb();
      }
    });
  }

  group('DefaultFoldGestureArbiter — settle arbitration', () {
    test('fold mid-drag: cancel once, commit once, restore once', () {
      final log = <String>[];
      final h = harness(log: log);
      final arbiter = h.arbiter;
      addTearDown(arbiter.dispose);

      arbiter.pointerDown(1);
      arbiter.markActivityInFlight();
      expect(arbiter.hasActivePointer, isTrue);

      arbiter.onFoldSettled(settle());
      h.flush();

      expect(log, ['stop', 'commit', 'restore']);
      expect(arbiter.hasInFlightActivity, isFalse);
      expect(arbiter.inFlightVelocity, 0);
      expect(arbiter.dragActive, isFalse);

      // The same settle delivered twice must not re-fire anything.
      final t = arbiter.lastSettled!;
      arbiter.onFoldSettled(t);
      h.flush();
      expect(log, ['stop', 'commit', 'restore']);
    });

    test('no velocity carry: a fling at fold becomes a stop', () {
      final log = <String>[];
      final h = harness(log: log);
      final arbiter = h.arbiter;
      addTearDown(arbiter.dispose);

      arbiter.pointerDown(1);
      arbiter.markActivityInFlight(velocity: 950);
      expect(arbiter.inFlightVelocity, 950);

      arbiter.onFoldSettled(settle());
      // Velocity is dropped at the settle, before any restore.
      expect(arbiter.inFlightVelocity, 0);
      expect(arbiter.hasInFlightActivity, isFalse);
      h.flush();
      expect(log.where((e) => e == 'stop').length, 1);
      expect(log.where((e) => e == 'restore').length, 1);
    });

    test('pointer count returns to zero after pointer-up post-fold', () {
      final h = harness();
      final arbiter = h.arbiter;
      addTearDown(arbiter.dispose);

      arbiter.pointerDown(1);
      arbiter.pointerDown(2);
      arbiter.markActivityInFlight();
      arbiter.onFoldSettled(settle());
      h.flush();

      // Late pointer-up after the fold must throw nothing and leak nothing.
      arbiter.pointerUp(1);
      arbiter.pointerUp(2);
      expect(arbiter.hasActivePointer, isFalse);
      arbiter.pointerUp(99); // unknown pointer: tolerated
      expect(arbiter.hasActivePointer, isFalse);
    });

    test('resting fold (no pointer): commit + restore once, no cancel', () {
      final log = <String>[];
      final h = harness(log: log);
      final arbiter = h.arbiter;
      addTearDown(arbiter.dispose);

      arbiter.onFoldSettled(settle());
      h.flush();
      expect(log, ['commit', 'restore']);
    });

    test('rapid settles before the frame seam: latest wins, one restore', () {
      final log = <String>[];
      final h = harness(log: log);
      final arbiter = h.arbiter;
      addTearDown(arbiter.dispose);

      arbiter.pointerDown(1);
      arbiter.markActivityInFlight(velocity: 400);
      arbiter.onFoldSettled(settle());
      arbiter.onFoldSettled(
        settle(previous: FoldState.innerPortrait, next: FoldState.cover),
      );
      h.flush();

      expect(log.where((e) => e == 'restore').length, 1);
      expect(log.where((e) => e == 'commit').length, 1);
      expect(arbiter.lastSettled!.next, FoldState.cover);
    });

    test('a fresh drag works after the fold', () {
      final h = harness();
      final arbiter = h.arbiter;
      addTearDown(arbiter.dispose);

      arbiter.pointerDown(1);
      arbiter.markActivityInFlight();
      arbiter.onFoldSettled(settle());
      arbiter.pointerUp(1);
      h.flush();

      arbiter.pointerDown(3);
      arbiter.markActivityInFlight();
      expect(arbiter.hasActivePointer, isTrue);
      expect(arbiter.hasInFlightActivity, isTrue);
      expect(arbiter.dragActive, isTrue);
      arbiter.markActivityIdle();
      arbiter.pointerUp(3);
      expect(arbiter.hasActivePointer, isFalse);
      expect(arbiter.hasInFlightActivity, isFalse);
    });
  });

  group('cancelInFlight', () {
    test('keepAnchor freezes at the anchor: commit exactly once', () {
      final log = <String>[];
      final h = harness(log: log);
      final arbiter = h.arbiter;
      addTearDown(arbiter.dispose);

      arbiter.pointerDown(1);
      arbiter.markActivityInFlight(velocity: 300);
      arbiter.cancelInFlight(keepAnchor: true);
      arbiter.cancelInFlight(keepAnchor: true); // idempotent commit

      expect(log.where((e) => e == 'commit').length, 1);
      expect(log.where((e) => e == 'stop').length, 2);
      expect(arbiter.inFlightVelocity, 0);
      expect(arbiter.dragActive, isFalse);
      expect(arbiter.hasInFlightActivity, isFalse);
      // Pointer tracking survives the cancel; up still lands cleanly.
      arbiter.pointerUp(1);
      expect(arbiter.hasActivePointer, isFalse);
    });

    test('keepAnchor false drops activity without committing', () {
      final log = <String>[];
      final h = harness(log: log);
      final arbiter = h.arbiter;
      addTearDown(arbiter.dispose);

      arbiter.markActivityInFlight(velocity: 300);
      arbiter.cancelInFlight(keepAnchor: false);
      expect(log, ['stop']);
      expect(arbiter.inFlightVelocity, 0);
    });
  });

  group('FoldGestureBoundary widget seam', () {
    testWidgets('forwards each settled transition to the arbiter exactly '
        'once and tracks pointers', (tester) async {
      tester.view.physicalSize = coverSize;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);

      final log = <String>[];
      final arbiter = DefaultFoldGestureArbiter(
        stopActivity: () => log.add('stop'),
        commitAnchor: () => log.add('commit'),
        restoreAnchor: () => log.add('restore'),
      );
      addTearDown(arbiter.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: FoldAwareShell(
            driver: driver,
            child: FoldGestureBoundary(
              arbiter: arbiter,
              child: GestureDetector(
                key: const ValueKey('surface'),
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // A pointer goes down on the gesture surface.
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('surface'))),
      );
      expect(arbiter.hasActivePointer, isTrue);
      arbiter.markActivityInFlight(velocity: 600);

      // Fold settles mid-drag. pump(1ms) fires the zero-debounce settle
      // timer; the same frame rebuilds under the new size and the post-frame
      // live-size report delivers the transition to the boundary.
      driver.report(FoldState.innerPortrait);
      tester.view.physicalSize = innerSize;
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(); // post-frame anchor restore

      expect(arbiter.lastSettled, isNotNull);
      expect(arbiter.lastSettled!.next, FoldState.innerPortrait);
      expect(log.where((e) => e == 'restore').length, 1);
      expect(log.where((e) => e == 'commit').length, 1);
      expect(arbiter.inFlightVelocity, 0);

      // Pointer-up after the fold: no exception, no leak, no re-fire.
      await gesture.up();
      await tester.pump();
      expect(arbiter.hasActivePointer, isFalse);
      expect(log.where((e) => e == 'restore').length, 1);

      // A fresh tap participates normally in the new geometry.
      await tester.tap(find.byKey(const ValueKey('surface')));
      await tester.pump();
      expect(arbiter.hasActivePointer, isFalse);
    });

    testWidgets('renders without a FoldLayoutScope above it', (tester) async {
      final arbiter = DefaultFoldGestureArbiter(
        stopActivity: () {},
        commitAnchor: () {},
        restoreAnchor: () {},
      );
      addTearDown(arbiter.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FoldGestureBoundary(
            arbiter: arbiter,
            child: const Text('plain'),
          ),
        ),
      );
      expect(find.text('plain'), findsOneWidget);
    });
  });
}
