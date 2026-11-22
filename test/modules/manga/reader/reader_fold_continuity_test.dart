import 'dart:io';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/core/fold/fold_state_provider.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/l10n/l10n_delegates.dart';
import 'package:mangayomi/main.dart' as app;
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/manga/reader/reader_view.dart';
import 'package:mangayomi/modules/manga/reader/subsampling_scale_image_view/subsampling_scale_image_view.dart'
    as ssiv;
import 'package:mangayomi/modules/manga/reader/u_chap_data_preload.dart';
import 'package:mangayomi/modules/manga/reader/utils/reader_page_index_math.dart';
import 'package:mangayomi/modules/manga/reader/widgets/double_page_view.dart';
import 'package:mangayomi/modules/manga/reader/widgets/reader_page_content.dart';
import 'package:mangayomi/providers/reader_state_provider.dart';
import 'package:mangayomi/providers/storage_provider.dart';
import 'package:mangayomi/services/get_chapter_pages.dart';
import 'package:shiori/shiori.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
// ignore: depend_on_referenced_packages
import 'package:wakelock_plus_platform_interface/messages.g.dart'
    show IsEnabledMessage, WakelockPlusApi;

/// AC-6: the manga reader keeps its page index across fold posture changes,
/// converts spread<->single correctly when doublePageAuto follows the
/// orientation, keeps zoom within 2% of its pre-fold value, and keeps page
/// imagery out of the 32pt crease band ([297,329] on the inner display).
/// Driven headlessly with [FakeFoldStateDriver] and pumped MediaQuery sizes.

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return crc ^ 0xFFFFFFFF;
}

/// A minimal valid 8-bit RGB PNG, solid colour, generated so the test needs
/// no binary assets and the SSIV native decoder has real pixels to read.
List<int> _pngBytes(int w, int h, int rgb) {
  final out = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  void chunk(String type, List<int> data) {
    out.addAll([
      (data.length >> 24) & 255,
      (data.length >> 16) & 255,
      (data.length >> 8) & 255,
      data.length & 255,
    ]);
    final body = <int>[...type.codeUnits, ...data];
    out.addAll(body);
    final crc = _crc32(body);
    out.addAll([
      (crc >> 24) & 255,
      (crc >> 16) & 255,
      (crc >> 8) & 255,
      crc & 255,
    ]);
  }

  chunk('IHDR', <int>[
    (w >> 24) & 255, (w >> 16) & 255, (w >> 8) & 255, w & 255, //
    (h >> 24) & 255, (h >> 16) & 255, (h >> 8) & 255, h & 255, //
    8, 2, 0, 0, 0,
  ]);
  final row = <int>[
    0,
    for (var x = 0; x < w; x++) ...[
      (rgb >> 16) & 255,
      (rgb >> 8) & 255,
      rgb & 255,
    ],
  ];
  final raw = <int>[for (var y = 0; y < h; y++) ...row];
  chunk('IDAT', ZLibEncoder().convert(raw));
  chunk('IEND', const []);
  return out;
}

void _mockReaderChannels() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  for (final name in const [
    'window_manager',
    'wakelock_plus',
    'com.kodjodevf.mangayomi.volume_keys',
    'screen_brightness',
    'plugins.flutter.io/path_provider',
  ]) {
    messenger.setMockMethodCallHandler(MethodChannel(name), (call) async =>
        null);
  }
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async =>
      null);
  // wakelock_plus talks over pigeon BasicMessageChannels. This pigeon
  // version casts the reply to List<Object?>? ([value] on success) and
  // encodes custom message classes with its own codec, so reply through
  // WakelockPlusApi.pigeonChannelCodec with the proper envelope.
  final wakelockCodec = WakelockPlusApi.pigeonChannelCodec;
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (message) async => wakelockCodec.encodeMessage(<Object?>[null]),
  );
  messenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.isEnabled',
    (message) async => wakelockCodec.encodeMessage(
      <Object?>[IsEnabledMessage(enabled: false)],
    ),
  );
}

ThemeData _theme() => buildShioriTheme(
  brightness: Brightness.light,
  colors: FlexColor.schemesList[2].light,
  tintSurfaces: false,
  blendLevel: 10,
  density: ShioriDensity.phone,
);

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int tries = 60,
}) async {
  for (var i = 0; i < tries && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Reports a settled posture and pumps past the SSIV resize debounce (150ms)
/// and any post-frame index conversion.
Future<void> _settle(
  WidgetTester tester,
  FakeFoldStateDriver driver,
  FoldState state,
  Size size,
) async {
  tester.view.physicalSize = size;
  driver.report(state);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 220));
  // The fold debounce fires during the 220ms pump above; SSIV then schedules
  // its own 150ms viewport-resize debounce. Pump past it so zoom preservation
  // has actually run before the assertions.
  await tester.pump(const Duration(milliseconds: 200));
}

Rect _rectOf(Element e) {
  final box = e.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Unmounts the widget tree after the test even when the body failed, then
/// drains real-event-loop completions so no fake-async Isar transaction is
/// left pending for tearDownAll's db.close().
void _autoUnmount(WidgetTester tester) {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
  });
}

/// Fixed-value override so a test can select its double-page behaviour
/// without an in-body Isar write: writeTxnSync deadlocks on the write lock
/// held by a pending fake-async transaction left over from a previous test.
class _FixedDoublePageAuto extends DoublePageAutoState {
  _FixedDoublePageAuto(this.value);
  final bool value;
  @override
  bool build() => value;
}

void main() {
  late Directory dir;
  late Isar db;
  late Manga manga;
  late Chapter chapter;
  late List<UChapDataPreload> pages;
  late GetChapterPagesModel model;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
    dir = await Directory.systemTemp.createTemp('mangayomi-fold-');
    db = await StorageProvider().initDB(dir.path);
    app.isar = db;
    manga = Manga(
      source: 'Demo',
      author: 'Author',
      artist: '',
      genre: const ['Drama'],
      imageUrl: null,
      lang: 'en',
      link: '/fold-series',
      name: 'Fold Series',
      status: Status.ongoing,
      description: 'A fold test series.',
      sourceId: null,
      favorite: true,
    );
    await db.writeTxn(() async {
      await db.mangas.put(manga);
      chapter = Chapter(
        mangaId: manga.id,
        name: 'Chapter 1',
        url: '/fold-c1',
      );
      await db.chapters.put(chapter);
      chapter.manga.value = manga;
      await chapter.manga.save();
      final settings = (await db.settings.get(227))!;
      settings.defaultReaderMode = ReaderMode.ltr;
      settings.doublePageAuto = true;
      settings.doublePageSingleFirstPage = false;
      // Forced doublePage for the auto=false test (portrait spread); the
      // auto=true tests resolve via orientation and ignore this list.
      settings.personalPageModeList = [
        PersonalPageMode(mangaId: manga.id, pageMode: PageMode.doublePage),
      ];
      await db.settings.put(settings);
    });
    pages = [];
    for (var i = 0; i < 8; i++) {
      final file = File('${dir.path}/page_$i.png');
      await file.writeAsBytes(_pngBytes(800, 1200, 0x3050A0 + i * 12));
      pages.add(
        UChapDataPreload(chapter, null, null, null, null, i, null, i)
          ..isLocale = true
          ..localImagePath = file.path
          ..loadedWidth = 800
          ..loadedHeight = 1200,
      );
    }
    await File('${dir.path}/wide.png')
        .writeAsBytes(_pngBytes(1600, 1000, 0xA03050));
    model = GetChapterPagesModel(
      path: null,
      pageUrls: [],
      isLocaleList: [],
      archiveImages: [],
      uChapDataPreload: pages,
      localImagePaths: [],
    );
  });

  tearDownAll(() async {
    // Bound the close: a fake-async transaction whose native completion was
    // never flushed would otherwise make Isar.close wait forever.
    await db.close(deleteFromDisk: true).timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        // ignore: avoid_print
        print('[C0] Isar close timed out: pending fake-async transaction?');
        return false;
      },
    );
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  setUp(_mockReaderChannels);

  // -------------------------------------------------------------------------
  // The full reader state machine: index preservation, spread<->single
  // conversion, and the single-page crease room.
  // -------------------------------------------------------------------------
  testWidgets(
    'AC-6 reader: page index survives folds, spread<->single converts, '
    'single page clears the crease',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);
      _autoUnmount(tester);

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [foldStateControllerProvider.overrideWithValue(driver)],
          child: MaterialApp(
            theme: _theme(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MangaChapterPageGallery(
              chapter: chapter,
              chapterUrlModel: model,
            ),
          ),
        ),
      );
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find
            .byType(ssiv.SubsamplingScaleImageView)
            .evaluate()
            .any((e) =>
                (e.widget as ssiv.SubsamplingScaleImageView)
                    .controller
                    ?.isReady ??
                false),
      );
      expect(tester.takeException(), isNull);

      PageController pageController() =>
          tester.widget<PageView>(find.byType(PageView)).controller!;

      // Cover: no crease, single page fills the viewport.
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(0, 0, 390, 844),
      );
      expect(pageController().page, 0);
      final coverImage = tester.getRect(
        find.byType(ssiv.SubsamplingScaleImageView).first,
      );
      expect(coverImage.left, moreOrLessEquals(0, epsilon: 0.5));
      expect(coverImage.width, moreOrLessEquals(390, epsilon: 0.5));

      // Read to actual page 2.
      pageController().jumpToPage(2);
      await tester.pump();
      expect(pageController().page, 2);

      // Inner portrait: still single (portrait), page moved to the right
      // room, index untouched.
      await _settle(tester, driver, FoldState.innerPortrait, const Size(626, 890));
      expect(pageController().page, 2);
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(329, 0, 626, 890),
      );
      // The crease band is viewport-centred and 32pt wide; every on-screen
      // page image must stay clear of it (right room for LTR).
      final portraitBand = FoldLayoutSpec.resolve(
        foldState: FoldState.innerPortrait,
        size: const Size(626, 890),
      ).creaseBand!;
      expect(portraitBand, const Rect.fromLTRB(297, 0, 329, 890));
      final portraitImages = find
          .byType(ssiv.SubsamplingScaleImageView)
          .evaluate()
          .map(_rectOf)
          .where((r) => r.left >= 0 && r.right <= 626)
          .toList();
      expect(portraitImages, isNotEmpty);
      for (final r in portraitImages) {
        expect(
          r.overlaps(portraitBand),
          isFalse,
          reason: 'page imagery $r straddles the crease $portraitBand',
        );
        expect(r.left, greaterThanOrEqualTo(328.5));
      }

      // Inner landscape: doublePageAuto switches to spreads. Actual page 2
      // lives in spread 1 (pages 2-3, singleFirst=false).
      await _settle(tester, driver, FoldState.innerLandscape, const Size(890, 626));
      expect(pageController().page, 1);
      expect(find.byKey(const ValueKey('spread_1_2_3')), findsOneWidget);
      final landscapeView = tester.getRect(find.byType(PageView));
      expect(landscapeView.top, greaterThanOrEqualTo(329));
      expect(landscapeView.bottom, lessThanOrEqualTo(626));
      // Horizontal band: the whole spread sits in the bottom room.
      final landscapeBand = FoldLayoutSpec.resolve(
        foldState: FoldState.innerLandscape,
        size: const Size(890, 626),
      ).creaseBand!;
      expect(landscapeBand, const Rect.fromLTRB(0, 297, 890, 329));
      final spreadRect = tester.getRect(find.byType(DoublePageView));
      expect(spreadRect.overlaps(landscapeBand), isFalse);
      expect(spreadRect.top, greaterThanOrEqualTo(328.5));

      // Back to inner portrait: single again, actual page 2 restored.
      await _settle(tester, driver, FoldState.innerPortrait, const Size(626, 890));
      expect(pageController().page, 2);
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(329, 0, 626, 890),
      );

      // Cover again: index still 2, full viewport.
      await _settle(tester, driver, FoldState.cover, const Size(390, 844));
      expect(pageController().page, 2);
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(0, 0, 390, 844),
      );

      // Unfold back to landscape: the spread containing page 2 returns
      // (round-trip entered from the spread side, not just the single side).
      await _settle(tester, driver, FoldState.innerLandscape, const Size(890, 626));
      expect(pageController().page, 1);
      expect(find.byKey(const ValueKey('spread_1_2_3')), findsOneWidget);

      // Drain the reader's mode-hint / delayed rebuild timers.
      await tester.pump(const Duration(seconds: 2));
    },
  );

  // -------------------------------------------------------------------------
  // The page content widget directly: spread gutter on the band, lone wide
  // pages in a room, and zoom preservation across viewport resizes.
  // -------------------------------------------------------------------------
  Future<void> pumpContent(
    WidgetTester tester, {
    required FakeFoldStateDriver driver,
    required Size size,
    required PageMode pageMode,
    required List<UChapDataPreload> contentPages,
    required Map<int, ssiv.SubsamplingScaleImageViewController> controllers,
    required PageController pageController,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    _autoUnmount(tester);
    final pageCount = pageMode == PageMode.doublePage
        ? ReaderPageIndexMath.buildSpreads(
            contentPages,
            singleFirst: false,
          ).length
        : contentPages.length;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: _theme(),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FoldAwareShell(
            driver: driver,
            child: Scaffold(
              body: ReaderPageContent(
                pages: contentPages,
                chapter: chapter,
                readerMode: ReaderMode.ltr,
                pageMode: pageMode,
                backgroundColor: BackgroundColor.black,
                pagePreloadAmount: 1,
                initialScrollIndex: 0,
                currentPageViewIndex: 0,
                pageViewPageCount: pageCount,
                isReverseHorizontal: false,
                isCurrentPageZoomed: false,
                listController: ListController(),
                continuousScrollController: ScrollController(),
                extendedController: pageController,
                scrollDirection: Axis.horizontal,
                pageControllerFor: (i) => controllers.putIfAbsent(
                  i,
                  () => ssiv.SubsamplingScaleImageViewController(),
                ),
                onFailedToLoadImage: (_, _) {},
                onWidePage: (_, _, _) {},
                onTallPage: (_, _, _) {},
                onPageImageLoaded: (_) {},
                onWideSinglePageLoaded: (_) {},
                onDoublePageZoomChanged: (_, _) {},
                onDoublePageControllerChanged: (_, _, _) {},
                onPageChanged: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'AC-6 spread: pages flank the 32pt band; a lone wide page gets a room',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.innerPortrait);
      addTearDown(driver.dispose);
      final controllers =
          <int, ssiv.SubsamplingScaleImageViewController>{};
      final pageController = PageController();
      addTearDown(pageController.dispose);

      await pumpContent(
        tester,
        driver: driver,
        size: const Size(626, 890),
        pageMode: PageMode.doublePage,
        contentPages: pages.sublist(0, 4),
        controllers: controllers,
        pageController: pageController,
      );
      await _pumpUntil(tester, () => controllers[0]?.isReady ?? false);
      await tester.pump(const Duration(milliseconds: 220));

      // The spread keeps the full viewport; the two page boxes flank the
      // [297,329] band with the gutter exactly on it.
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(0, 0, 626, 890),
      );
      final pageBoxes = find
          .byWidgetPredicate((w) {
            final k = w.key;
            return k is ValueKey && k.value.toString().startsWith('dp_page_');
          })
          .evaluate()
          .map(_rectOf)
          .where((r) => r.left >= 0 && r.right <= 626)
          .toList();
      expect(pageBoxes.length, 2);
      final left = pageBoxes.firstWhere((r) => r.left < 297);
      final right = pageBoxes.firstWhere((r) => r.left >= 329);
      expect(left.right, lessThanOrEqualTo(297));
      expect(right.left, greaterThanOrEqualTo(329));
      expect(right.left - left.right, moreOrLessEquals(32, epsilon: 0.5));

      // On the cover the spread keeps the legacy flush layout (no gutter).
      await _settle(tester, driver, FoldState.cover, const Size(390, 844));
      final coverBoxes = find
          .byWidgetPredicate((w) {
            final k = w.key;
            return k is ValueKey && k.value.toString().startsWith('dp_page_');
          })
          .evaluate()
          .map(_rectOf)
          .where((r) => r.left >= 0 && r.right <= 390)
          .toList()
        ..sort((a, b) => a.left.compareTo(b.left));
      expect(coverBoxes.length, 2);
      expect(coverBoxes[1].left - coverBoxes[0].right, lessThanOrEqualTo(0.5));
      // Restore the posture for the lone-wide-page case below.
      await _settle(tester, driver, FoldState.innerPortrait, const Size(626, 890));

      // A lone wide page in a spread must not straddle the band either.
      // wide.png was generated in setUpAll; dart:io writes must not be awaited
      // inside the fake-async test body (they would never complete).
      final wideFile = File('${dir.path}/wide.png');
      final widePages = [
        UChapDataPreload(chapter, null, null, null, null, 0, null, 0)
          ..isLocale = true
          ..localImagePath = wideFile.path
          ..loadedWidth = 1600
          ..loadedHeight = 1000,
        pages[1],
        pages[2],
      ];
      final wideController = PageController();
      addTearDown(wideController.dispose);
      await pumpContent(
        tester,
        driver: driver,
        size: const Size(626, 890),
        pageMode: PageMode.doublePage,
        contentPages: widePages,
        controllers: controllers,
        pageController: wideController,
      );
      await tester.pump(const Duration(milliseconds: 220));
      final loneSpread = tester.getRect(find.byType(DoublePageView));
      expect(loneSpread.left, greaterThanOrEqualTo(329));
      expect(loneSpread.right, lessThanOrEqualTo(626));
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'AC-6 zoom: relative zoom survives fold resizes within 2%',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);
      final controllers =
          <int, ssiv.SubsamplingScaleImageViewController>{};
      final pageController = PageController();
      addTearDown(pageController.dispose);

      await pumpContent(
        tester,
        driver: driver,
        size: const Size(390, 844),
        pageMode: PageMode.onePage,
        contentPages: pages.sublist(0, 3),
        controllers: controllers,
        pageController: pageController,
      );
      await _pumpUntil(tester, () => controllers[0]?.isReady ?? false);
      expect(controllers[0]!.isReady, isTrue,
          reason: 'SSIV native decoder did not load the fixture PNG');
      await tester.pump(const Duration(milliseconds: 220));

      final controller = controllers[0]!;
      double ratio() => controller.scale / controller.minScale;
      expect(ratio(), moreOrLessEquals(1.0, epsilon: 0.02));

      // Zoom to 1.75x fit, then fold through every posture.
      controller.setScaleAndCenter(
        controller.minScale * 1.75,
        const Offset(400, 600),
      );
      await tester.pump();
      final zoomed = ratio();
      expect(zoomed, moreOrLessEquals(1.75, epsilon: 0.05));

      await _settle(tester, driver, FoldState.innerPortrait, const Size(626, 890));
      expect(ratio(), moreOrLessEquals(zoomed, epsilon: zoomed * 0.02));
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(329, 0, 626, 890),
      );

      await _settle(tester, driver, FoldState.innerLandscape, const Size(890, 626));
      expect(ratio(), moreOrLessEquals(zoomed, epsilon: zoomed * 0.02));
      final landscapeView = tester.getRect(find.byType(PageView));
      expect(landscapeView.top, greaterThanOrEqualTo(329));

      await _settle(tester, driver, FoldState.cover, const Size(390, 844));
      expect(ratio(), moreOrLessEquals(zoomed, epsilon: zoomed * 0.02));
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(0, 0, 390, 844),
      );

      // A higher zoom factor (2.5x fit) must also survive portrait<->cover.
      controller.setScaleAndCenter(
        controller.minScale * 2.5,
        const Offset(400, 600),
      );
      await tester.pump();
      final zoomedHigh = ratio();
      expect(zoomedHigh, moreOrLessEquals(2.5, epsilon: 0.05));
      await _settle(tester, driver, FoldState.innerPortrait, const Size(626, 890));
      expect(ratio(), moreOrLessEquals(zoomedHigh, epsilon: zoomedHigh * 0.02));
      await _settle(tester, driver, FoldState.cover, const Size(390, 844));
      final afterHigh = ratio();
      expect((afterHigh - zoomedHigh).abs() / zoomedHigh, lessThan(0.02));
      expect(afterHigh, greaterThan(2.0), reason: 'zoom was reset to fit');
      await tester.pump(const Duration(seconds: 2));
    },
  );

  // -------------------------------------------------------------------------
  // Forced double page (doublePageAuto=false): portrait spreads flank the
  // band, and the cover keeps the legacy flush spread layout.
  // -------------------------------------------------------------------------
  testWidgets(
    'AC-6 forced spread: auto=false keeps portrait spreads on the band; '
    'cover stays flush',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.innerPortrait);
      addTearDown(driver.dispose);
      _autoUnmount(tester);

      tester.view.physicalSize = const Size(626, 890);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            foldStateControllerProvider.overrideWithValue(driver),
            doublePageAutoStateProvider.overrideWith(
              () => _FixedDoublePageAuto(false),
            ),
          ],
          child: MaterialApp(
            theme: _theme(),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MangaChapterPageGallery(
              chapter: chapter,
              chapterUrlModel: model,
            ),
          ),
        ),
      );
      await tester.pump();
      await _pumpUntil(
        tester,
        () => find.byType(DoublePageView).evaluate().isNotEmpty,
      );
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.takeException(), isNull);
      expect(find.byType(DoublePageView), findsOneWidget);

      List<Rect> pageBoxes(double width) => find
          .byWidgetPredicate((w) {
            final k = w.key;
            return k is ValueKey && k.value.toString().startsWith('dp_page_');
          })
          .evaluate()
          .map(_rectOf)
          .where((r) => r.left >= 0 && r.right <= width)
          .toList()
        ..sort((a, b) => a.left.compareTo(b.left));

      // Portrait with auto=false: the forced personal page mode keeps a
      // spread whose pages flank the [297,329] band with a 32pt gutter.
      final band = FoldLayoutSpec.resolve(
        foldState: FoldState.innerPortrait,
        size: const Size(626, 890),
      ).creaseBand!;
      expect(band, const Rect.fromLTRB(297, 0, 329, 890));
      final boxes = pageBoxes(626);
      expect(boxes.length, 2);
      expect(boxes[0].overlaps(band), isFalse);
      expect(boxes[1].overlaps(band), isFalse);
      expect(boxes[0].right, lessThanOrEqualTo(297.5));
      expect(boxes[1].left, greaterThanOrEqualTo(328.5));
      expect(boxes[1].left - boxes[0].right, moreOrLessEquals(32, epsilon: 0.5));

      // Fold to the cover: still a spread (forced), but flush — no gutter.
      await _settle(tester, driver, FoldState.cover, const Size(390, 844));
      expect(find.byType(DoublePageView), findsOneWidget);
      final coverBoxes = pageBoxes(390);
      expect(coverBoxes.length, 2);
      expect(coverBoxes[1].left - coverBoxes[0].right, lessThanOrEqualTo(0.5));

      // Drain the reader's mode-hint / delayed rebuild timers.
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
