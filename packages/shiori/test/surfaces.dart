/// The foldable's two panes, and the harness that mounts a component on
/// either, so every new behaviour is watched at the size a reader meets it.
library;

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/shiori.dart';

/// The narrow, cover-like pane: the outside of the fold.
const Size shioriCoverPane = Size(466, 678);

/// The wide pane the device unfolds to.
const Size shioriInnerPane = Size(890, 626);

/// Every pane the app is read on.
const List<Size> shioriPanes = [shioriCoverPane, shioriInnerPane];

/// The theme the component tests mount, at the density under test.
ThemeData shioriTestTheme({ShioriDensity density = ShioriDensity.phone}) =>
    buildShioriTheme(
      brightness: Brightness.dark,
      colors: FlexColor.schemesList[2].dark,
      tintSurfaces: false,
      blendLevel: 10,
      density: density,
    );

/// Mounts [child] on [pane] under the Shiori theme, and pumps one frame.
Future<void> pumpOnPane(
  WidgetTester tester,
  Widget child, {
  Size pane = shioriInnerPane,
  ShioriDensity density = ShioriDensity.phone,
  bool disableAnimations = false,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = pane;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: shioriTestTheme(density: density),
      home: MediaQuery(
        data: MediaQueryData(
          size: pane,
          disableAnimations: disableAnimations,
          reduceMotion: reduceMotion,
        ),
        child: Scaffold(body: child),
      ),
    ),
  );
}
