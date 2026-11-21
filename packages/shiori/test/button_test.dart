import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/shiori.dart';

import 'surfaces.dart';

/// The button is the most touched surface in the interface: every state it
/// can be in — pressed, held, busy, unavailable — is a state a reader meets.
void main() {
  // The drawn scale, read from the Transform widget the AnimatedScale
  // builds. The matrix entry, not `getMaxScaleOnAxis`: that takes the
  // maximum across x, y and z, and the z of a 2D scale is always 1.
  double drawnScale(WidgetTester tester) => tester
      .widget<Transform>(
        find
            .ancestor(
              of: find.byType(FilledButton),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform
      .entry(0, 0);

  group('ShioriButton press feedback', () {
    for (final pane in shioriPanes) {
      testWidgets('a touch presses the button while it lasts '
          '(${pane.width.truncate()}×${pane.height.truncate()})', (
        tester,
      ) async {
        await pumpOnPane(
          tester,
          Center(
            child: ShioriButton(label: 'Resume', onPressed: () {}),
          ),
          pane: pane,
        );

        expect(drawnScale(tester), 1);

        final gesture = await tester.startGesture(
          tester.getCenter(find.text('Resume')),
        );
        // The first frame registers the press and starts the movement;
        // the next one is half of it.
        await tester.pump();
        await tester.pump(ShioriMotion.fast ~/ 2);

        // On its way down: strictly between rest and the pressed scale,
        // and still travelling.
        expect(
          drawnScale(tester),
          inExclusiveRange(ShioriMotion.pressedScale, 1),
        );
        expect(tester.hasRunningAnimations, isTrue);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(drawnScale(tester), 1);
        expect(tester.hasRunningAnimations, isFalse);
      });
    }

    testWidgets('presses on the motion tokens, never its own timing', (
      tester,
    ) async {
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton(label: 'Resume', onPressed: () {}),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Resume')),
      );
      await tester.pump();
      await tester.pump(ShioriMotion.fast ~/ 2);
      final atHalf = drawnScale(tester);

      // Half way through the fast token, and no further.
      expect(atHalf, inExclusiveRange(ShioriMotion.pressedScale, 1));
      await tester.pump(ShioriMotion.fast ~/ 2);
      // Exactly done at the token's duration: earlier is too soon, longer
      // would still be on its way.
      expect(drawnScale(tester), ShioriMotion.pressedScale);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(drawnScale(tester), 1);
    });

    testWidgets('an unavailable button gives no press feedback', (
      tester,
    ) async {
      await pumpOnPane(
        tester,
        const Center(child: ShioriButton(label: 'Resume', onPressed: null)),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Resume')),
      );
      await tester.pump(ShioriMotion.fast);

      expect(drawnScale(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('holds still when the platform asks for no animation', (
      tester,
    ) async {
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton(label: 'Resume', onPressed: () {}),
        ),
        disableAnimations: true,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Resume')),
      );
      await tester.pump(const Duration(milliseconds: 1));

      // The state lands without travelling: at 1 ms into a 120 ms movement
      // it would still be at rest. Material's own ink is Material's
      // business; this is about the button's own feedback.
      expect(drawnScale(tester), ShioriMotion.pressedScale);
      await gesture.up();
      await tester.pump(ShioriMotion.fast);
      expect(drawnScale(tester), 1);
    });

    testWidgets('a press that slides off the button still lets go', (
      tester,
    ) async {
      await pumpOnPane(
        tester,
        const Align(
          alignment: Alignment.center,
          child: ShioriButton(label: 'Resume', onPressed: null),
        ),
      );
      // A move far off the button, then the finger comes up.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Resume')),
      );
      await tester.pump(ShioriMotion.fast ~/ 2);
      await gesture.moveTo(const Offset(600, 600));
      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(drawnScale(tester), 1);
    });
  });

  group('ShioriButton loading', () {
    testWidgets('a loading button spins in place of its icon and holds its '
        'name', (tester) async {
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton(
            label: 'Saving…',
            icon: Symbols.save_rounded,
            loading: true,
            onPressed: () {},
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Symbols.save_rounded), findsNothing);
      expect(find.text('Saving…'), findsOneWidget);
    });

    testWidgets('a loading button ignores taps', (tester) async {
      var saved = false;
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton(
            label: 'Save',
            loading: true,
            onPressed: () => saved = true,
          ),
        ),
      );

      await tester.tap(find.text('Save'));
      // Bounded, not pumpAndSettle: an indeterminate spinner never settles,
      // and the point is only that the tap has landed.
      await tester.pump();
      expect(saved, isFalse);
    });

    testWidgets('a loading button says it cannot be used yet', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton(label: 'Save', loading: true, onPressed: () {}),
        ),
      );

      expect(
        tester.getSemantics(find.text('Save')),
        matchesSemantics(label: 'Save', isButton: true, hasEnabledState: true),
      );
      handle.dispose();
    });

    testWidgets('a loading button gives no press feedback either', (
      tester,
    ) async {
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton(label: 'Save', loading: true, onPressed: () {}),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Save')),
      );
      await tester.pump(ShioriMotion.fast);

      expect(drawnScale(tester), 1);
      await gesture.up();
      // Bounded: the spinner keeps the frame busy, but the press animation
      // must be done.
      await tester.pump(ShioriMotion.fast);
    });

    testWidgets('a quiet button loads the same way', (tester) async {
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton.quiet(
            label: 'Check for updates',
            loading: true,
            onPressed: () {},
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(TextButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
    });
  });

  group('ShioriButton targets and names', () {
    testWidgets('never smaller than the touch floor, even for a mouse', (
      tester,
    ) async {
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton.quiet(label: 'Cancel', onPressed: () {}),
        ),
        density: ShioriDensity.desktop,
      );

      expect(
        tester.getSize(find.byType(TextButton)).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('a phone keeps its own, larger floor', (tester) async {
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton(label: 'Resume', onPressed: () {}),
        ),
      );

      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(ShioriDensity.phone.minTarget),
      );
    });

    testWidgets('names its action for a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpOnPane(
        tester,
        Center(
          child: ShioriButton(label: 'Add to library', onPressed: () {}),
        ),
      );

      expect(
        tester.getSemantics(find.text('Add to library')),
        matchesSemantics(
          label: 'Add to library',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });
  });
}
