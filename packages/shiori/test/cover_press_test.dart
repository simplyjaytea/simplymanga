import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/shiori.dart';

import 'surfaces.dart';

/// The cover is the app's card: a touch that opens a series is met with
/// the same weight a button answers with.
void main() {
  // The drawn scale of a cover, from the Transform its AnimatedScale
  // builds. The matrix entry: `getMaxScaleOnAxis` is always 1 for a 2D
  // scale, because it also measures the z axis.
  double coverScale(WidgetTester tester) => tester
      .widget<Transform>(
        find.descendant(
          of: find.byType(ShioriCover),
          matching: find.byType(Transform),
        ),
      )
      .transform
      .entry(0, 0);

  Widget cover({VoidCallback? onTap, VoidCallback? onLongPress}) => Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 120,
      child: ShioriCover(
        image: null,
        title: 'Frieren',
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    ),
  );

  group('ShioriCover press feedback', () {
    for (final pane in shioriPanes) {
      testWidgets('a touch presses the cover while it lasts '
          '(${pane.width.truncate()}×${pane.height.truncate()})', (
        tester,
      ) async {
        var opened = false;
        await pumpOnPane(tester, cover(onTap: () => opened = true), pane: pane);

        expect(coverScale(tester), 1);

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ShioriCover)),
        );
        await tester.pump();
        await tester.pump(ShioriMotion.fast ~/ 2);

        expect(
          coverScale(tester),
          inExclusiveRange(ShioriMotion.pressedScale, 1),
        );

        await gesture.up();
        await tester.pumpAndSettle();
        expect(coverScale(tester), 1);
        expect(opened, isTrue);
      });
    }

    testWidgets('a cover held for its long press presses too', (tester) async {
      var held = false;
      await pumpOnPane(tester, cover(onLongPress: () => held = true));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ShioriCover)),
      );
      await tester.pump();
      await tester.pump(ShioriMotion.fast);

      expect(coverScale(tester), ShioriMotion.pressedScale);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(coverScale(tester), 1);
      expect(held, isFalse);
    });

    testWidgets('a cover without an action gives no feedback', (tester) async {
      await pumpOnPane(tester, cover());

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ShioriCover)),
      );
      await tester.pump();
      await tester.pump(ShioriMotion.fast);

      expect(coverScale(tester), 1);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('lands without travelling when animations are off', (
      tester,
    ) async {
      await pumpOnPane(tester, cover(onTap: () {}), disableAnimations: true);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(ShioriCover)),
      );
      await tester.pump(const Duration(milliseconds: 1));

      expect(coverScale(tester), ShioriMotion.pressedScale);
      await gesture.up();
      await tester.pump(ShioriMotion.fast);
      expect(coverScale(tester), 1);
    });
  });
}
