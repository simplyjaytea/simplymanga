import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/core/fold/fold_state_provider.dart';
import 'package:mangayomi/modules/main_view/widgets/tablet_layout.dart';
import 'package:mangayomi/modules/widgets/gridview_widget.dart';
import 'package:shiori/shiori.dart';

/// Production-shell regression for HIGH-1.
///
/// [FoldLayoutSpec.creaseBand] is expressed in SHELL/window coordinates. The
/// existing fold_grid_test pumps the grid full-width and hands the delegate a
/// pre-shifted band, so it never sees the navigation rail. In the real tablet
/// shell the rail occupies the first 100px, so the grid's origin is at shell
/// x=100 and the protected gutter must be shifted into the grid's true frame —
/// otherwise it lands 100px to the right of the actual hinge.
///
/// This pumps the library grid INSIDE the rail-bearing [MainTabletLayout] with
/// the fold scope resolved at window size, and asserts the gutter centres on the
/// TRUE hinge (shell W/2), not W/2 + rail.
void main() {
  testWidgets(
    'library grid inside the 100px rail shell keeps covers clear of the true '
    'hinge and centres the gutter on shell W/2 (HIGH-1)',
    (tester) async {
      const size = Size(626, 890); // innerPortrait, rail visible
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final driver = FakeFoldStateDriver(FoldState.innerPortrait);
      addTearDown(driver.dispose);

      const railWidth = 100.0;
      final hingeX = size.width / 2; // 313 — the TRUE hinge in shell coords
      final hingeBand = Rect.fromLTRB(
        hingeX - FoldLayoutSpec.creaseBandWidth / 2,
        0,
        hingeX + FoldLayoutSpec.creaseBandWidth / 2,
        size.height,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [foldStateControllerProvider.overrideWithValue(driver)],
          child: MaterialApp(
            theme: buildShioriTheme(
              brightness: Brightness.dark,
              colors: FlexColor.schemesList[2].dark,
              tintSurfaces: false,
              blendLevel: 10,
              density: ShioriDensity.phone,
            ),
            // Scope resolved at WINDOW size, above the rail-bearing shell.
            home: FoldAwareShell(
              driver: driver,
              child: Consumer(
                builder: (context, ref, _) => MainTabletLayout(
                  isLongPressed: false,
                  location: '/MangaLibrary', // rail width = 100
                  dest: const ['/MangaLibrary', '/AnimeLibrary'],
                  currentIndex: 0,
                  route: GoRouter(
                    routes: [
                      GoRoute(path: '/', builder: (_, _) => const SizedBox()),
                    ],
                  ),
                  ref: ref,
                  buildNavigationWidgetsDesktop: (ref, dest, context) => const [
                    NavigationRailDestination(
                      icon: Icon(Icons.book_rounded),
                      label: Text('Manga'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.movie_rounded),
                      label: Text('Anime'),
                    ),
                  ],
                  child: GridViewWidget(
                    itemCount: 12,
                    childAspectRatio: 0.7,
                    itemBuilder: (context, index) => ColoredBox(
                      color: Colors.blue,
                      child: SizedBox.expand(key: ValueKey('cover-$index')),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Sanity: the rail really offsets the grid by 100px in this shell.
      final gridRect = tester.getRect(find.byType(GridViewWidget));
      expect(gridRect.left, railWidth);

      // No cover may straddle the TRUE hinge band (shell W/2 ± 16).
      final coverRects = <Rect>[];
      for (var i = 0; i < 12; i++) {
        final finder = find.byKey(ValueKey('cover-$i'));
        if (finder.evaluate().isEmpty) continue;
        coverRects.add(tester.getRect(finder));
      }
      expect(coverRects, isNotEmpty);
      for (final rect in coverRects) {
        expect(
          rect.overlaps(hingeBand),
          isFalse,
          reason: 'cover $rect straddles the true hinge band $hingeBand',
        );
      }

      // The gutter is centred on the hinge: covers sit on both sides of it and
      // nothing occupies the band, i.e. the gap is at shell W/2, not W/2 + rail.
      expect(coverRects.any((r) => r.right <= hingeBand.left), isTrue);
      expect(coverRects.any((r) => r.left >= hingeBand.right), isTrue);
    },
  );
}
