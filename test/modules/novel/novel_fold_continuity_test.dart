import 'dart:async';

import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/l10n/l10n_delegates.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/novel/mixins/novel_pagination_tts_mixin.dart';
import 'package:mangayomi/modules/novel/novel_reader_controller_provider.dart';
import 'package:mangayomi/modules/novel/utils/novel_paginator.dart';
import 'package:mangayomi/src/rust/api/epub.dart';
import 'package:shiori/shiori.dart';

/// AC-7: the novel reader re-paginates at most once per settled posture
/// (PLAN M6), preserves reading position across re-pagination, and keeps
/// text out of the 32pt crease band. Driven headlessly with
/// [FakeFoldStateDriver] and pumped MediaQuery sizes.
String _fixtureHtml() {
  final buffer = StringBuffer('<div id="readerViewContent">');
  for (int i = 0; i < 60; i++) {
    buffer.write(
      '<p data-tts-index="$i">Paragraph $i: the quick brown fox jumps over '
      'the lazy dog while the fold crease waits patiently in the middle of '
      'the inner display, refusing to be read through.</p>',
    );
  }
  buffer.write('</div>');
  return buffer.toString();
}

/// The mixin only calls setChapterOffset on the controller; a noSuchMethod
/// stub keeps the test free of Isar and the reading-session repository.
class _StubNovelController implements NovelReaderController {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NovelHost extends ConsumerStatefulWidget {
  const _NovelHost({required this.driver, required this.pageMode});
  final FoldStateDriver driver;
  final PageMode pageMode;
  @override
  ConsumerState<_NovelHost> createState() => _NovelHostState();
}

class _NovelHostState extends ConsumerState<_NovelHost>
    with NovelPaginationAndTtsMixin<_NovelHost> {
  final Chapter _chapter = Chapter(mangaId: 1, name: 'fold-test');
  final _StubNovelController _controller = _StubNovelController();

  @override
  Chapter get chapter => _chapter;
  @override
  EpubNovel? get epubBook => null;
  @override
  NovelReaderController get readerController => _controller;
  @override
  final ScrollController scrollController = ScrollController();
  @override
  final StreamController<double> rebuildDetail =
      StreamController<double>.broadcast();
  @override
  double offset = 0;
  @override
  double maxOffset = 0;
  @override
  bool scrolled = false;
  @override
  bool scrollRestoreScheduled = false;

  @override
  void initState() {
    super.initState();
    lastEffectivePageMode = widget.pageMode;
  }

  @override
  void dispose() {
    spreadController.dispose();
    scrollController.dispose();
    rebuildDetail.close();
    ttsProgress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FoldAwareShell(
      driver: widget.driver,
      child: Builder(
        builder: (context) => buildPaginatedSpreadView(
          effectivePageMode: widget.pageMode,
          htmlData: _fixtureHtml(),
          fontSize: 16,
          lineHeight: 1.5,
          padding: 12,
          fontFamily: null,
          removeExtraSpacing: false,
          textAlignEnum: TextAlign.left,
          parsedTextColor: const Color(0xFF101010),
          parsedBackgroundColor: const Color(0xFFFDFDFD),
          tts: (paragraph: -1, wordStart: -1, wordEnd: -1),
        ),
      ),
    );
  }
}

void main() {
  Future<_NovelHostState> pumpHost(
    WidgetTester tester, {
    required FoldStateDriver driver,
    required PageMode pageMode,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildShioriTheme(
            brightness: Brightness.light,
            colors: FlexColor.schemesList[2].light,
            tintSurfaces: false,
            blendLevel: 10,
            density: ShioriDensity.phone,
          ),
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _NovelHost(driver: driver, pageMode: pageMode),
        ),
      ),
    );
    await tester.pump();
    return tester.state<_NovelHostState>(find.byType(_NovelHost));
  }

  testWidgets(
    'AC-7 single page: one re-pagination per settled posture, position '
    'preserved, text clears the crease',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);

      final host = await pumpHost(
        tester,
        driver: driver,
        pageMode: PageMode.onePage,
        size: const Size(390, 844),
      );
      NovelPaginationResult? seen;
      var paginations = 0;
      void tally() {
        if (!identical(host.cachedPagination, seen)) {
          paginations++;
          seen = host.cachedPagination;
        }
      }

      tally();
      expect(paginations, 1);
      expect(host.cachedPagination!.pageCount, greaterThan(3));
      // Cover has no crease: the page fills the viewport.
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(0, 0, 390, 844),
      );

      // Read to page 2 and remember the progress.
      host.spreadController.jumpToPage(2);
      await tester.pump();
      expect(host.currentSpreadIndex, 2);
      final progressBefore = host.cachedPagination!.progressForPage(2);

      // Fold to inner portrait: exactly ONE new pagination.
      tester.view.physicalSize = const Size(626, 890);
      driver.report(FoldState.innerPortrait);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      tally();
      expect(paginations, 2);
      final progressAfter = host.cachedPagination!.progressForPage(
        host.currentSpreadIndex,
      );
      expect((progressAfter - progressBefore).abs(), lessThan(0.12));
      // The page lives in the right room, clear of the [297,329] band.
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(329, 0, 626, 890),
      );

      // M6 churn: intermediate fold frames must NOT re-paginate, even when
      // live geometry crosses the square point mid-animation.
      for (final size in [
        const Size(500, 870),
        const Size(560, 880),
        const Size(700, 800),
        const Size(800, 700),
        const Size(626, 890),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        tally();
        expect(paginations, 2);
      }

      // Inner landscape: one new pagination, text below the horizontal band.
      tester.view.physicalSize = const Size(890, 626);
      driver.report(FoldState.innerLandscape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      tally();
      expect(paginations, 3);
      final landscapeProgress = host.cachedPagination!.progressForPage(
        host.currentSpreadIndex,
      );
      expect((landscapeProgress - progressBefore).abs(), lessThan(0.15));
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(0, 329, 890, 626),
      );

      // Back to cover: one new pagination, position preserved.
      tester.view.physicalSize = const Size(390, 844);
      driver.report(FoldState.cover);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      tally();
      expect(paginations, 4);
      final coverProgress = host.cachedPagination!.progressForPage(
        host.currentSpreadIndex,
      );
      expect((coverProgress - progressBefore).abs(), lessThan(0.12));
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(0, 0, 390, 844),
      );
    },
  );

  testWidgets(
    'AC-7 double page: spread pages flank the crease band and position '
    'survives re-pagination',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final driver = FakeFoldStateDriver(FoldState.cover);
      addTearDown(driver.dispose);

      final host = await pumpHost(
        tester,
        driver: driver,
        pageMode: PageMode.doublePage,
        size: const Size(390, 844),
      );
      NovelPaginationResult? seen;
      var paginations = 0;
      void tally() {
        if (!identical(host.cachedPagination, seen)) {
          paginations++;
          seen = host.cachedPagination;
        }
      }

      tally();
      expect(paginations, 1);
      expect(host.cachedPagination!.spreadCount, greaterThan(2));

      host.spreadController.jumpToPage(1);
      await tester.pump();
      expect(host.currentSpreadIndex, 1);
      final progressBefore = host.cachedPagination!.progressForSpread(1);

      // Inner portrait: one new pagination; pages flank the 32pt band.
      tester.view.physicalSize = const Size(626, 890);
      driver.report(FoldState.innerPortrait);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      tally();
      expect(paginations, 2);
      final progressAfter = host.cachedPagination!.progressForSpread(
        host.currentSpreadIndex,
      );
      expect((progressAfter - progressBefore).abs(), lessThan(0.15));
      expect(
        tester.getRect(find.byType(PageView)),
        const Rect.fromLTRB(0, 0, 626, 890),
      );
      final pageViewRect = tester.getRect(find.byType(PageView));
      // Exclude the PageView's own viewport clip; only page-content clips
      // must clear the crease band.
      final clipRects = find
          .descendant(
            of: find.byType(PageView),
            matching: find.byType(ClipRect),
          )
          .evaluate()
          .map((e) {
            final box = e.renderObject! as RenderBox;
            return box.localToGlobal(Offset.zero) & box.size;
          })
          .where((r) => r.left >= 0 && r.right <= 626 && r != pageViewRect)
          .toList();
      expect(clipRects, isNotEmpty);
      for (final r in clipRects) {
        expect(
          r.right <= 297 || r.left >= 329,
          isTrue,
          reason: 'page content inside the crease band: $r',
        );
      }
      expect(clipRects.any((r) => r.right <= 297), isTrue);
      expect(clipRects.any((r) => r.left >= 329), isTrue);

      // M6 churn: no re-pagination on intermediate frames, including
      // square-point crossings while the settled posture is unchanged.
      for (final size in [
        const Size(540, 880),
        const Size(700, 800),
        const Size(800, 700),
      ]) {
        tester.view.physicalSize = size;
        await tester.pump();
        tally();
        expect(paginations, 2);
      }

      // Inner landscape: the whole spread moves below the horizontal band.
      tester.view.physicalSize = const Size(890, 626);
      driver.report(FoldState.innerLandscape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      tally();
      expect(paginations, 3);
      final landscapeProgress = host.cachedPagination!.progressForSpread(
        host.currentSpreadIndex,
      );
      expect((landscapeProgress - progressBefore).abs(), lessThan(0.15));
      final landscapePageView = tester.getRect(find.byType(PageView));
      expect(landscapePageView.top, greaterThanOrEqualTo(329));
      expect(landscapePageView.bottom, lessThanOrEqualTo(626));

      // Back to cover: one new pagination, position preserved.
      tester.view.physicalSize = const Size(390, 844);
      driver.report(FoldState.cover);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      tally();
      expect(paginations, 4);
      final coverProgress = host.cachedPagination!.progressForSpread(
        host.currentSpreadIndex,
      );
      expect((coverProgress - progressBefore).abs(), lessThan(0.15));
    },
  );
}
