import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/models/chapter.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/manga/reader/u_chap_data_preload.dart';
import 'package:mangayomi/modules/manga/reader/utils/reader_split_engine.dart';

/// C1 spec 3.3-3.7: the pure split resolver. Pure Rect/Size + page stubs;
/// no widget tree, no Isar. FoldReaderRooms is the geometry authority and
/// ReaderPageIndexMath.buildSpreads is the grouping authority.
void main() {
  const cover = Size(390, 844);
  const innerPortrait = Size(626, 890);
  const innerLandscape = Size(890, 626);
  const portraitBand = Rect.fromLTRB(297, 0, 329, 890);
  const landscapeBand = Rect.fromLTRB(0, 297, 890, 329);
  const leftRoom = Rect.fromLTRB(0, 0, 297, 890);
  const rightRoom = Rect.fromLTRB(329, 0, 626, 890);

  final ch1 = Chapter(id: 101, mangaId: 1, name: 'Chapter 1');
  final ch2 = Chapter(id: 102, mangaId: 1, name: 'Chapter 2');

  UChapDataPreload page(
    Chapter ch,
    int index, {
    double w = 800,
    double h = 1200,
  }) {
    final p = UChapDataPreload(ch, null, null, null, null, index, null, index);
    p.loadedWidth = w;
    p.loadedHeight = h;
    return p;
  }

  UChapDataPreload wide(Chapter ch, int index) =>
      page(ch, index, w: 1600, h: 1000);

  UChapDataPreload transition(int pageIndex) => UChapDataPreload.transition(
    currentChapter: ch1,
    nextChapter: ch2,
    mangaName: 'Test Manga',
    pageIndex: pageIndex,
  );

  List<UChapDataPreload> portraitPages(int count) =>
      List.generate(count, (i) => page(ch1, i));

  FoldLayoutSpec specFor(FoldState state, Size size) =>
      FoldLayoutSpec.resolve(foldState: state, size: size);

  const engine = ReaderSplitEngine();

  ReaderSplitPlan resolve({
    FoldState state = FoldState.innerPortrait,
    Size viewport = innerPortrait,
    PageMode pageMode = PageMode.doublePage,
    bool rtl = false,
    required int anchor,
    required List<UChapDataPreload> pages,
    bool singleFirst = false,
  }) => engine.resolve(
    spec: specFor(state, viewport),
    viewport: viewport,
    pageMode: pageMode,
    rtl: rtl,
    anchorActualIndex: anchor,
    pages: pages,
    singleFirst: singleFirst,
  );

  group('T2 — anchor conversion (odd anchor survives the merge)', () {
    test('onePage -> doublePage keeps anchor 3 as the facing page', () {
      final pages = portraitPages(6);
      final single = resolve(
        pageMode: PageMode.onePage,
        anchor: 3,
        pages: pages,
      );
      expect(single.mode, ReaderSplitMode.single);
      expect(single.anchorActualIndex, 3);
      expect(single.pageViewIndex, 3);
      expect(single.pageViewCount, 6);

      final spread = resolve(anchor: 3, pages: pages);
      expect(spread.mode, ReaderSplitMode.spread);
      expect(spread.anchorActualIndex, 3);
      expect(spread.anchorIsSecond, isTrue);
      expect(spread.pageViewIndex, 1); // spread (2,3)
      expect(spread.pageViewCount, 3);
    });

    test('doublePage -> onePage returns the stored anchor 3, NOT 2', () {
      final pages = portraitPages(6);
      final merged = resolve(
        pageMode: PageMode.onePage,
        anchor: 3,
        pages: pages,
      );
      expect(merged.anchorActualIndex, 3);
      expect(merged.pageViewIndex, 3); // not spread.firstIndex (2)
      expect(merged.anchorIsSecond, isFalse);
    });

    test('anchor on the first page of a spread is not second', () {
      final plan = resolve(anchor: 2, pages: portraitPages(6));
      expect(plan.pageViewIndex, 1);
      expect(plan.anchorIsSecond, isFalse);
      expect(plan.anchorActualIndex, 2);
    });
  });

  group('T3 — spread flanks the vertical band', () {
    test('LTR: anchor page left, facing page right, gap 32 +/- 0.5', () {
      final plan = resolve(anchor: 2, pages: portraitPages(6));
      expect(plan.mode, ReaderSplitMode.spread);
      expect(plan.creaseBand, portraitBand);
      expect(plan.primaryRoom, leftRoom);
      expect(plan.facingRoom, rightRoom);
      expect(plan.primaryRoom.right, lessThanOrEqualTo(297));
      expect(plan.facingRoom!.left, greaterThanOrEqualTo(329));
      expect(
        plan.facingRoom!.left - plan.primaryRoom.right,
        closeTo(32, 0.5),
      );
      expect(plan.gutter, closeTo(32, 0.5));
    });

    test('RTL: reading order preserved, visual order mirrored', () {
      final plan = resolve(anchor: 2, pages: portraitPages(6), rtl: true);
      expect(plan.primaryRoom, rightRoom); // first page on the right
      expect(plan.facingRoom, leftRoom);
      expect(plan.gutter, closeTo(32, 0.5));
    });

    test('RTL anchor on the second page docks it to the left room', () {
      final plan = resolve(anchor: 3, pages: portraitPages(6), rtl: true);
      expect(plan.anchorIsSecond, isTrue);
      expect(plan.primaryRoom, leftRoom);
      expect(plan.facingRoom, rightRoom);
    });
  });

  group('T4 — inner landscape splits the LOWER room', () {
    test('spread sits below the horizontal band with a hairline divider', () {
      final plan = resolve(
        state: FoldState.innerLandscape,
        viewport: innerLandscape,
        anchor: 0,
        pages: portraitPages(4),
      );
      expect(plan.mode, ReaderSplitMode.spread);
      expect(plan.creaseBand, landscapeBand);
      expect(plan.primaryRoom.top, greaterThanOrEqualTo(329));
      expect(plan.facingRoom!.top, greaterThanOrEqualTo(329));
      // Lower room [0,329,890,626] split into two equal pages.
      expect(plan.primaryRoom, const Rect.fromLTRB(0, 329, 445, 626));
      expect(plan.facingRoom, const Rect.fromLTRB(445, 329, 890, 626));
      expect(plan.primaryRoom.width, plan.facingRoom!.width);
      expect(plan.gutter, 1); // hairline, not the physical band
    });

    test('single page in landscape uses the full-width lower room', () {
      final plan = resolve(
        state: FoldState.innerLandscape,
        viewport: innerLandscape,
        pageMode: PageMode.onePage,
        anchor: 1,
        pages: portraitPages(4),
      );
      expect(plan.mode, ReaderSplitMode.single);
      expect(plan.primaryRoom, const Rect.fromLTRB(0, 329, 890, 626));
      expect(plan.facingRoom, isNull);
      expect(plan.gutter, 0);
    });
  });

  group('T5 — wide solo page crosses the crease deliberately (C-1)', () {
    test('wide page in doublePage mode is FULL viewport, not one room', () {
      final pages = [
        page(ch1, 0),
        page(ch1, 1),
        wide(ch1, 2),
        page(ch1, 3),
        page(ch1, 4),
      ];
      final plan = resolve(anchor: 2, pages: pages);
      expect(plan.mode, ReaderSplitMode.soloWide);
      expect(plan.primaryRoom, const Rect.fromLTRB(0, 0, 626, 890));
      expect(plan.primaryRoom.center, const Offset(313, 445));
      expect(plan.facingRoom, isNull);
      expect(plan.gutter, 0);
      expect(plan.anchorActualIndex, 2);
      expect(plan.pageViewIndex, 1); // spreads: (0,1),(2),(3,4)
      expect(plan.pageViewCount, 3);
      // Explicitly NOT docked to a single room.
      expect(plan.primaryRoom, isNot(rightRoom));
      expect(plan.primaryRoom, isNot(leftRoom));
    });

    test('wide page in onePage mode is still full viewport centred', () {
      final pages = [page(ch1, 0), wide(ch1, 1), page(ch1, 2)];
      final plan = resolve(
        pageMode: PageMode.onePage,
        anchor: 1,
        pages: pages,
      );
      expect(plan.mode, ReaderSplitMode.soloWide);
      expect(plan.primaryRoom, const Rect.fromLTRB(0, 0, 626, 890));
      expect(plan.pageViewIndex, 1);
      expect(plan.pageViewCount, 3);
    });

    test('wide solo on cover stays full viewport with no band', () {
      final plan = resolve(
        state: FoldState.cover,
        viewport: cover,
        anchor: 0,
        pages: [wide(ch1, 0)],
      );
      expect(plan.mode, ReaderSplitMode.soloWide);
      expect(plan.primaryRoom, const Rect.fromLTRB(0, 0, 390, 844));
      expect(plan.creaseBand, isNull);
    });
  });

  group('T6 — solo portrait pages dock to ONE room', () {
    test('transition page is solo, never paired, never crosses the band', () {
      final pages = [
        page(ch1, 0),
        page(ch1, 1),
        page(ch1, 2),
        transition(3),
        page(ch2, 0),
        page(ch2, 1),
      ];
      final plan = resolve(anchor: 3, pages: pages);
      expect(plan.mode, ReaderSplitMode.single);
      expect(plan.primaryRoom, rightRoom);
      expect(plan.facingRoom, isNull);
      expect(plan.primaryRoom.left, greaterThanOrEqualTo(329));
      expect(plan.gutter, 0);
    });

    test('odd tail page is solo in one room', () {
      final plan = resolve(anchor: 4, pages: portraitPages(5));
      expect(plan.mode, ReaderSplitMode.single);
      expect(plan.primaryRoom, rightRoom);
      expect(plan.facingRoom, isNull);
      expect(plan.pageViewIndex, 2); // (0,1),(2,3),(4)
      expect(plan.pageViewCount, 3);
    });

    test('chapter boundary: last page of an odd chapter never pairs', () {
      final pages = [
        page(ch1, 0),
        page(ch1, 1),
        page(ch1, 2),
        transition(3),
        page(ch2, 0),
        page(ch2, 1),
      ];
      final plan = resolve(anchor: 2, pages: pages);
      expect(plan.mode, ReaderSplitMode.single);
      expect(plan.facingRoom, isNull);
      expect(plan.primaryRoom, rightRoom);
    });

    test('singleFirst: first page solo, pairing starts at page 2', () {
      final pages = portraitPages(6);
      final first = resolve(anchor: 0, pages: pages, singleFirst: true);
      expect(first.mode, ReaderSplitMode.single);
      expect(first.primaryRoom, rightRoom);
      expect(first.pageViewCount, 4); // (0),(1,2),(3,4),(5)

      final second = resolve(anchor: 1, pages: pages, singleFirst: true);
      expect(second.mode, ReaderSplitMode.spread);
      expect(second.pageViewIndex, 1);
      expect(second.anchorIsSecond, isFalse);
    });

    test('RTL solo portrait page docks to the left room', () {
      final plan = resolve(
        pageMode: PageMode.onePage,
        anchor: 4,
        pages: portraitPages(5),
        rtl: true,
      );
      expect(plan.mode, ReaderSplitMode.single);
      expect(plan.primaryRoom, leftRoom);
    });
  });

  group('T15 — RTL mirror', () {
    test('single page left; spread first page right', () {
      final pages = portraitPages(4);
      final single = resolve(
        pageMode: PageMode.onePage,
        anchor: 1,
        pages: pages,
        rtl: true,
      );
      expect(single.primaryRoom, leftRoom);

      final spread = resolve(anchor: 0, pages: pages, rtl: true);
      expect(spread.primaryRoom, rightRoom); // first page on the right
      expect(spread.facingRoom, leftRoom);
    });
  });

  group('cover / unknown / edge cases', () {
    test('cover single page: full viewport, no band, one column', () {
      final plan = resolve(
        state: FoldState.cover,
        viewport: cover,
        pageMode: PageMode.onePage,
        anchor: 2,
        pages: portraitPages(6),
      );
      expect(plan.mode, ReaderSplitMode.single);
      expect(plan.primaryRoom, const Rect.fromLTRB(0, 0, 390, 844));
      expect(plan.creaseBand, isNull);
      expect(plan.facingRoom, isNull);
      expect(plan.gutter, 0);
      expect(plan.pageViewIndex, 2);
      expect(plan.pageViewCount, 6);
    });

    test('explicit doublePage on cover halves the viewport, gutter 0', () {
      final plan = resolve(
        state: FoldState.cover,
        viewport: cover,
        anchor: 0,
        pages: portraitPages(4),
      );
      expect(plan.mode, ReaderSplitMode.spread);
      expect(plan.creaseBand, isNull);
      expect(plan.primaryRoom, const Rect.fromLTRB(0, 0, 195, 844));
      expect(plan.facingRoom, const Rect.fromLTRB(195, 0, 390, 844));
      expect(plan.gutter, 0);
    });

    test('unknown posture invents no crease', () {
      final plan = resolve(
        state: FoldState.unknown,
        viewport: innerPortrait,
        pageMode: PageMode.onePage,
        anchor: 0,
        pages: portraitPages(2),
      );
      expect(plan.creaseBand, isNull);
      expect(plan.primaryRoom, const Rect.fromLTRB(0, 0, 626, 890));
    });

    test('empty page list resolves without crashing', () {
      final plan = resolve(anchor: 0, pages: const []);
      expect(plan.mode, ReaderSplitMode.single);
      expect(plan.pageViewIndex, 0);
      expect(plan.pageViewCount, 0);
    });

    test('out-of-range anchor clamps to the nearest valid page', () {
      final plan = resolve(anchor: 99, pages: portraitPages(4));
      expect(plan.anchorActualIndex, 3);
      expect(plan.pageViewIndex, 1); // spread (2,3)
      expect(plan.anchorIsSecond, isTrue);
    });

    test('unloaded dimensions are treated as portrait (no invented wide)', () {
      final p = UChapDataPreload(ch1, null, null, null, null, 0, null, 0);
      final plan = resolve(
        pageMode: PageMode.onePage,
        anchor: 0,
        pages: [p],
      );
      expect(plan.mode, ReaderSplitMode.single);
      expect(plan.primaryRoom, rightRoom);
    });
  });
}
