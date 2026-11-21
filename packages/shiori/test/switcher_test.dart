import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/shiori.dart';

import 'surfaces.dart';

/// One piece of content replacing another in the same place: the switch
/// the whole interface draws from, so no two screens invent their own.
void main() {
  Widget switching(Widget child, {ShioriSwitchMode? mode}) => Align(
    alignment: Alignment.topLeft,
    child: mode == null
        ? ShioriSwitcher(child: child)
        : ShioriSwitcher(mode: mode, child: child),
  );

  testWidgets('cross-fades one child into the next', (tester) async {
    await pumpOnPane(
      tester,
      switching(const Text('arrival', key: ValueKey(1))),
    );
    await pumpOnPane(
      tester,
      switching(const Text('departure', key: ValueKey(2))),
    );
    await tester.pump(ShioriMotion.medium ~/ 2);

    // Both present for the whole switch: no frame with neither on screen.
    expect(find.text('arrival', skipOffstage: false), findsOneWidget);
    expect(find.text('departure', skipOffstage: false), findsOneWidget);
    final arriving = tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.text('departure'),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    expect(arriving, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.text('departure', skipOffstage: false), findsOneWidget);
    expect(find.text('arrival', skipOffstage: false), findsNothing);
  });

  group('movement', () {
    Offset slideOf(WidgetTester tester, String label) => tester
        .widget<SlideTransition>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(SlideTransition),
          ),
        )
        .position
        .value;

    testWidgets('a rising switch lifts the new child in', (tester) async {
      await pumpOnPane(
        tester,
        switching(
          const Text('low', key: ValueKey(1)),
          mode: ShioriSwitchMode.rise,
        ),
      );
      await pumpOnPane(
        tester,
        switching(
          const Text('high', key: ValueKey(2)),
          mode: ShioriSwitchMode.rise,
        ),
      );
      await tester.pump(ShioriMotion.medium ~/ 2);

      expect(slideOf(tester, 'high').dy, inExclusiveRange(0, 0.5));
      await tester.pumpAndSettle();
      expect(slideOf(tester, 'high'), Offset.zero);
    });

    testWidgets('slides in from the trailing edge', (tester) async {
      await pumpOnPane(
        tester,
        switching(
          const Text('start', key: ValueKey(1)),
          mode: ShioriSwitchMode.slideEnd,
        ),
      );
      await pumpOnPane(
        tester,
        switching(
          const Text('end', key: ValueKey(2)),
          mode: ShioriSwitchMode.slideEnd,
        ),
      );
      await tester.pump(ShioriMotion.medium ~/ 2);

      expect(slideOf(tester, 'end').dx, greaterThan(0));
      await tester.pumpAndSettle();
      expect(slideOf(tester, 'end'), Offset.zero);
    });

    testWidgets('slides in from the leading edge', (tester) async {
      await pumpOnPane(
        tester,
        switching(
          const Text('one', key: ValueKey(1)),
          mode: ShioriSwitchMode.slideStart,
        ),
      );
      await pumpOnPane(
        tester,
        switching(
          const Text('two', key: ValueKey(2)),
          mode: ShioriSwitchMode.slideStart,
        ),
      );
      await tester.pump(ShioriMotion.medium ~/ 2);

      expect(slideOf(tester, 'two').dx, lessThan(0));
      await tester.pumpAndSettle();
      expect(slideOf(tester, 'two'), Offset.zero);
    });

    testWidgets('edges follow the writing direction', (tester) async {
      Widget rtl(Widget child) => Align(
        alignment: Alignment.topLeft,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ShioriSwitcher(mode: ShioriSwitchMode.slideEnd, child: child),
        ),
      );
      await pumpOnPane(tester, rtl(const Text('a', key: ValueKey(1))));
      await pumpOnPane(tester, rtl(const Text('b', key: ValueKey(2))));
      await tester.pump(ShioriMotion.medium ~/ 2);

      // The trailing edge of an RTL layout is the left one.
      expect(slideOf(tester, 'b').dx, lessThan(0));
      await tester.pumpAndSettle();
      expect(slideOf(tester, 'b'), Offset.zero);
    });
  });

  group('tokens and settings', () {
    testWidgets('switches on the medium token unless told otherwise', (
      tester,
    ) async {
      await pumpOnPane(tester, switching(const Text('a')));
      var switcher = tester.widget<AnimatedSwitcher>(
        find.byType(AnimatedSwitcher),
      );
      expect(switcher.duration, ShioriMotion.medium);
      expect(switcher.switchInCurve, ShioriMotion.decelerateCurve);
      expect(switcher.switchOutCurve, ShioriMotion.accelerateCurve);

      await pumpOnPane(
        tester,
        ShioriSwitcher(duration: ShioriMotion.slow, child: const Text('a')),
      );
      switcher = tester.widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher));
      expect(switcher.duration, ShioriMotion.slow);
    });

    testWidgets('a movement fades instead under "Reduce Motion"', (
      tester,
    ) async {
      await pumpOnPane(
        tester,
        switching(
          const Text('still', key: ValueKey(1)),
          mode: ShioriSwitchMode.slideEnd,
        ),
        reduceMotion: true,
      );
      await pumpOnPane(
        tester,
        switching(
          const Text('calm', key: ValueKey(2)),
          mode: ShioriSwitchMode.slideEnd,
        ),
        reduceMotion: true,
      );
      await tester.pump(ShioriMotion.medium ~/ 2);

      // No movement — but still a cross-fade, not a cut.
      expect(
        find.ancestor(
          of: find.text('calm'),
          matching: find.byType(SlideTransition),
        ),
        findsNothing,
      );
      expect(tester.hasRunningAnimations, isTrue);
      final arriving = tester
          .widget<FadeTransition>(
            find
                .ancestor(
                  of: find.text('calm'),
                  matching: find.byType(FadeTransition),
                )
                .first,
          )
          .opacity
          .value;
      expect(arriving, inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
    });

    testWidgets('is simply there when animations are off', (tester) async {
      await pumpOnPane(
        tester,
        switching(const Text('first', key: ValueKey(1))),
        disableAnimations: true,
      );
      await pumpOnPane(
        tester,
        switching(const Text('second', key: ValueKey(2))),
        disableAnimations: true,
      );
      // Nothing here loops; settling just lets the instant switch finish
      // removing the child it replaced.
      await tester.pumpAndSettle();

      expect(find.text('second', skipOffstage: false), findsOneWidget);
      expect(find.text('first', skipOffstage: false), findsNothing);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('on both panes', () {
    for (final pane in shioriPanes) {
      testWidgets(
        'rises on the ${pane.width.truncate()}×${pane.height.truncate()} pane',
        (tester) async {
          await pumpOnPane(
            tester,
            switching(
              const Text('a', key: ValueKey(1)),
              mode: ShioriSwitchMode.rise,
            ),
            pane: pane,
          );
          await pumpOnPane(
            tester,
            switching(
              const Text('b', key: ValueKey(2)),
              mode: ShioriSwitchMode.rise,
            ),
            pane: pane,
          );
          await tester.pump(ShioriMotion.medium ~/ 2);

          expect(find.text('a', skipOffstage: false), findsOneWidget);
          expect(tester.hasRunningAnimations, isTrue);
          await tester.pumpAndSettle();
          expect(find.text('b', skipOffstage: false), findsOneWidget);
        },
      );
    }
  });
}
