import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/shiori.dart';

/// The motion scale: one set of durations and curves every transition draws
/// from, so two animations a reader sees in the same second never disagree
/// about how long a movement takes.
void main() {
  group('durations', () {
    test('the fast / medium / slow scale is complete', () {
      expect(ShioriMotion.fast, const Duration(milliseconds: 120));
      expect(ShioriMotion.medium, const Duration(milliseconds: 220));
      expect(ShioriMotion.slow, const Duration(milliseconds: 350));
    });

    test('is one scale under two vocabularies', () {
      // "Medium" and "slow" are the standard and enter durations by their
      // other names; a caller may think in either, never both ways about the
      // same movement.
      expect(ShioriMotion.medium, ShioriMotion.standard);
      expect(ShioriMotion.slow, ShioriMotion.enter);

      // And the scale stays ordered however it is named.
      expect(ShioriMotion.fast.compareTo(ShioriMotion.medium), lessThan(0));
      expect(ShioriMotion.medium.compareTo(ShioriMotion.slow), lessThan(0));
      expect(ShioriMotion.slow.compareTo(ShioriMotion.exitSlow), lessThan(0));
    });
  });

  group('curves', () {
    test('the four named curves are complete', () {
      for (final curve in [
        ShioriMotion.standardCurve,
        ShioriMotion.emphasizedCurve,
        ShioriMotion.decelerateCurve,
        ShioriMotion.accelerateCurve,
      ]) {
        expect(curve.transform(0), 0);
        expect(curve.transform(1), 1);
      }
    });

    test('decelerate is well underway by half the duration', () {
      // Arrivals on this curve are seen from their first frames, which is
      // the point of an arrival.
      expect(ShioriMotion.decelerateCurve.transform(0.5), greaterThan(0.5));
      expect(
        ShioriMotion.decelerateCurve.transform(0.5),
        greaterThan(ShioriMotion.standardCurve.transform(0.5)),
      );
    });

    test('accelerate gathers before it goes', () {
      // Departures stay near where they were useful, then are gone.
      expect(ShioriMotion.accelerateCurve.transform(0.5), lessThan(0.5));
    });

    test('emphasized is the arrival curve under its other name', () {
      for (final t in [0.1, 0.3, 0.5, 0.7, 0.9]) {
        expect(
          ShioriMotion.emphasizedCurve.transform(t),
          closeTo(ShioriMotion.enterCurve.transform(t), 1e-9),
        );
      }
    });

    test('accelerate is the exit curve under its other name', () {
      for (final t in [0.1, 0.3, 0.5, 0.7, 0.9]) {
        expect(
          ShioriMotion.accelerateCurve.transform(t),
          closeTo(ShioriMotion.exitCurve.transform(t), 1e-9),
        );
      }
    });
  });

  group('press feedback', () {
    test('has a token of its own', () {
      // A press is a state change, not a movement: it stays a short step
      // from rest, never a full shrink.
      expect(ShioriMotion.pressedScale, inExclusiveRange(0.9, 1.0));
    });
  });
}
