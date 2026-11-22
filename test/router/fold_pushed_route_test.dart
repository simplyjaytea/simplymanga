import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/core/fold/fold_state_provider.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/l10n/l10n_delegates.dart';
import 'package:mangayomi/main.dart' as app;
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/anime/widgets/mobile_player_controls_layout.dart';
import 'package:mangayomi/modules/manga/detail/manga_detail_main.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/router/router.dart';
import 'package:shiori/shiori.dart';

/// Production-route regression for HIGH-2 / HIGH-3.
///
/// The isolated fold tests hand a [FoldAwareShell] straight to the widget under
/// test, so they stay green even though the *production* root builder never
/// hoisted a [FoldLayoutScope] above the Navigator. Detail and player are
/// top-level routes on the ROOT navigator, so `FoldLayoutScope.maybeOf` was
/// null there and the crease clearance was inert.
///
/// These tests pump the REAL root-builder artifact ([app.FoldRootScope]) above a
/// real [GoRouter] and push the production routes, so they fail until the
/// settled layout contract is actually hoisted above the Navigator.
void main() {
  late Directory dir;
  late Isar db;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    dir = await Directory.systemTemp.createTemp('mangayomi-foldroute-');
    db = await StorageProvider().initDB(dir.path);
    app.isar = db;
    final manga = Manga(
      source: 'Demo',
      author: 'Author',
      artist: '',
      genre: const ['Drama'],
      imageUrl: null,
      lang: 'en',
      link: '/series',
      name: 'Series',
      status: Status.ongoing,
      description: 'A description.',
      sourceId: null,
      favorite: true,
    );
    await db.writeTxn(() async {
      await db.mangas.put(manga);
      for (var i = 3; i >= 1; i--) {
        final chapter = Chapter(
          mangaId: manga.id,
          name: 'Chapter $i',
          isRead: i == 1,
        );
        await db.chapters.put(chapter);
        chapter.manga.value = manga;
        await chapter.manga.save();
      }
    });
  });

  tearDownAll(() async {
    await db.close(deleteFromDisk: true);
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Widget routedApp({required GoRouter router, required FakeFoldStateDriver driver}) {
    return ProviderScope(
      overrides: [foldStateControllerProvider.overrideWithValue(driver)],
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildShioriTheme(
          brightness: Brightness.dark,
          colors: FlexColor.schemesList[2].dark,
          tintSurfaces: false,
          blendLevel: 10,
          density: ShioriDensity.phone,
        ),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // The production root-builder hoist, not a hand-fed FoldAwareShell.
        builder: (context, child) => app.FoldRootScope(child: child!),
      ),
    );
  }

  Future<void> settleDb(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'pushed detail route on inner portrait sees the settled crease and renders '
    'the hinge gutter (HIGH-2)',
    (tester) async {
      const size = Size(626, 890); // innerPortrait
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final driver = FakeFoldStateDriver(FoldState.innerPortrait);
      addTearDown(driver.dispose);

      final manga = await tester.runAsync(() => db.mangas.where().findFirst());
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
          ),
          // Same page-building path as lib/router/router.dart.
          GoRoute(
            path: '/manga-reader/detail',
            pageBuilder: (context, state) => transitionPage(
              key: state.pageKey,
              child: routeChild<int>(
                route: '/manga-reader/detail',
                builder: (id) => MangaReaderDetail(mangaId: id),
                extra: state.extra,
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(routedApp(router: router, driver: driver));
      router.push('/manga-reader/detail', extra: manga!.id);
      // The detail page runs a repeating animation/timer, so pumpAndSettle
      // never settles; pump a fixed duration past the route transition and the
      // 120ms fold debounce, then let the Isar load complete. The crease gutter
      // depends only on the settled scope, not on the animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settleDb(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Series'), findsWidgets);

      // The settled layout contract must reach the pushed root-navigator route.
      final detailContext = tester.element(find.byType(MangaReaderDetail));
      final scope = FoldLayoutScope.maybeOf(detailContext);
      expect(
        scope,
        isNotNull,
        reason: 'FoldLayoutScope must be hoisted above the root Navigator',
      );
      expect(scope!.spec.foldState, FoldState.innerPortrait);
      expect(scope.spec.usesTwoPaneDetail, isTrue);

      // The vertical crease band is centred on the true hinge (window W/2).
      final hingeX = size.width / 2;
      final band = scope.spec.creaseBand;
      expect(band, isNotNull);
      expect((band!.center.dx - hingeX).abs(), lessThan(1.0));

      // The detail renders its clearance gutter centred on that hinge, so the
      // two panes sit either side of the crease rather than straddling it.
      final gutterWidth = FoldLayoutSpec.creaseBandWidth + 2 * ShioriSpace.s16;
      final gutterFinder = find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == gutterWidth,
      );
      var hingeGutterFound = false;
      for (var i = 0; i < gutterFinder.evaluate().length; i++) {
        final rect = tester.getRect(gutterFinder.at(i));
        if ((rect.center.dx - hingeX).abs() < 1.0) {
          hingeGutterFound = true;
          break;
        }
      }
      expect(
        hingeGutterFound,
        isTrue,
        reason: 'a ${gutterWidth}px crease gutter must be centred on the hinge',
      );
    },
  );

  testWidgets(
    'pushed player route on inner landscape pins controls below the horizontal '
    'crease (HIGH-3)',
    (tester) async {
      const size = Size(890, 626); // innerLandscape
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final driver = FakeFoldStateDriver(FoldState.innerLandscape);
      addTearDown(driver.dispose);

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Center(child: Text('home'))),
          ),
          // The canonical relocation path used by the player Stack
          // (lib/modules/anime/widgets/mobile.dart). The native mpv surface is
          // not pumpable in a widget test, so the route hosts the overlay layout
          // that actually performs the crease relocation.
          GoRoute(
            path: '/animePlayerView',
            pageBuilder: (context, state) => transitionPage(
              key: state.pageKey,
              child: const Scaffold(
                backgroundColor: Colors.black,
                body: Stack(
                  children: [
                    MobilePlayerControlsOverlayLayout(
                      compactPortrait: false,
                      safeInsets: EdgeInsets.zero,
                      topControls: SizedBox(height: 24),
                      primaryControls: SizedBox(height: 40),
                      bottomControls: SizedBox(height: 80),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(routedApp(router: router, driver: driver));
      router.push('/animePlayerView');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);

      final overlayContext = tester.element(
        find.byType(MobilePlayerControlsOverlayLayout),
      );
      final region = FoldLayoutScope.maybeOf(overlayContext)?.spec.controlsRegion;
      expect(
        region,
        isNotNull,
        reason: 'controlsRegion must reach the pushed player route',
      );

      // The controls are pinned to the far room below the horizontal crease.
      final controls = tester.getRect(
        find.byKey(const ValueKey('mobile-player-controls-overlay-wide')),
      );
      expect(controls.top, region!.top);
      expect(controls.top, greaterThan(size.height / 2));
      expect(controls.bottom, size.height);
    },
  );
}
