import 'dart:ui';

import 'package:mangayomi/core/fold/crease_rooms.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/manga/reader/u_chap_data_preload.dart';
import 'package:mangayomi/modules/manga/reader/utils/reader_page_index_math.dart';

/// How one settled PageView item occupies the crease-aware viewport
/// (C1 spec 3.7).
enum ReaderSplitMode {
  /// One portrait page docked to a single room.
  single,

  /// Two portrait pages flanking the crease, one per room.
  spread,

  /// A wide page deliberately crossing the crease, full viewport centred
  /// (spec 3.5 C-1) — NOT docked to one room.
  soloWide,
}

/// The pure split decision for one anchor page (C1 spec 3.7).
///
/// Everything a renderer needs to place the current PageView item without
/// touching a widget tree: mode, room rects, the crease band, the gutter and
/// the anchor/page-view index mapping. Computed only at settle — never per
/// live metrics tick.
class ReaderSplitPlan {
  const ReaderSplitPlan({
    required this.mode,
    required this.primaryRoom,
    this.facingRoom,
    this.creaseBand,
    required this.gutter,
    required this.anchorActualIndex,
    required this.anchorIsSecond,
    required this.pageViewIndex,
    required this.pageViewCount,
  });

  final ReaderSplitMode mode;

  /// Room holding the anchor page. [ReaderSplitMode.soloWide] uses the FULL
  /// viewport here (centred content), not a single room.
  final Rect primaryRoom;

  /// The other room of a spread; null for solo modes.
  final Rect? facingRoom;

  /// The physical dead band, when the posture has one; null on cover/unknown.
  final Rect? creaseBand;

  /// 32 for a vertical-band spread (the physical band), a hairline for the
  /// landscape lower-room split, 0 when no band separates the pages.
  final double gutter;

  /// The actual page index the reader is anchored on.
  final int anchorActualIndex;

  /// True when the anchor is the second page of its spread (spec 3.6).
  final bool anchorIsSecond;

  /// Index of the spread/item inside the settled PageView.
  final int pageViewIndex;

  /// Total items in the settled PageView.
  final int pageViewCount;
}

/// Pure split resolver (C1 spec 3.3-3.7). No widgets, no controllers, no
/// side effects: geometry comes from [FoldReaderRooms] (the single authority)
/// and grouping/anchor math from [ReaderPageIndexMath.buildSpreads].
class ReaderSplitEngine {
  const ReaderSplitEngine();

  // shiori: no Shiori hairline token exists; 1px is the spec 3.3 divider for
  // the landscape lower-room split (not a spacing value).
  static const double hairlineDivider = 1;

  /// Resolves the split plan for [anchorActualIndex] under a settled posture.
  ///
  /// [spec] is the settled [FoldLayoutSpec]; [viewport] the live size it was
  /// resolved for. [pageMode] is the effective page mode (doublePageAuto is
  /// resolved by the caller before reaching this pure layer). [rtl] mirrors
  /// room assignment without changing reading order. [singleFirst] keeps the
  /// first page solo (existing reader setting).
  ReaderSplitPlan resolve({
    required FoldLayoutSpec spec,
    required Size viewport,
    required PageMode pageMode,
    required bool rtl,
    required int anchorActualIndex,
    required List<UChapDataPreload> pages,
    bool singleFirst = false,
  }) {
    final rooms = FoldReaderRooms(spec: spec, viewport: viewport);
    final fullViewport = rooms.fullViewport;

    if (pages.isEmpty) {
      return ReaderSplitPlan(
        mode: ReaderSplitMode.single,
        primaryRoom: rooms.singlePageRoom(rtl: rtl),
        creaseBand: spec.creaseBand,
        gutter: 0,
        anchorActualIndex: 0,
        anchorIsSecond: false,
        pageViewIndex: 0,
        pageViewCount: 0,
      );
    }

    final anchor = anchorActualIndex.clamp(0, pages.length - 1);
    final anchorPage = pages[anchor];
    final isWide =
        anchorPage.loadedWidth != null &&
        anchorPage.loadedHeight != null &&
        anchorPage.loadedHeight! > 0 &&
        anchorPage.loadedWidth! > anchorPage.loadedHeight!;

    // C-1 (spec 3.5): a wide page is always soloWide, full viewport centred,
    // regardless of page mode. It deliberately crosses the crease.
    if (isWide) {
      return ReaderSplitPlan(
        mode: ReaderSplitMode.soloWide,
        primaryRoom: fullViewport,
        creaseBand: spec.creaseBand,
        gutter: 0,
        anchorActualIndex: anchor,
        anchorIsSecond: false,
        pageViewIndex: _pageViewIndexOf(
          pages: pages,
          pageMode: pageMode,
          anchor: anchor,
          singleFirst: singleFirst,
        ),
        pageViewCount: _pageViewCountOf(
          pages: pages,
          pageMode: pageMode,
          singleFirst: singleFirst,
        ),
      );
    }

    // Solo portrait pages (onePage mode, transitions, odd tails, chapter
    // boundaries, wide neighbours) dock to ONE room, flush to the crease.
    if (pageMode == PageMode.onePage ||
        !_isSpreadable(pages, anchor, singleFirst)) {
      return ReaderSplitPlan(
        mode: ReaderSplitMode.single,
        primaryRoom: rooms.singlePageRoom(rtl: rtl),
        creaseBand: spec.creaseBand,
        gutter: 0,
        anchorActualIndex: anchor,
        anchorIsSecond: false,
        pageViewIndex: _pageViewIndexOf(
          pages: pages,
          pageMode: pageMode,
          anchor: anchor,
          singleFirst: singleFirst,
        ),
        pageViewCount: _pageViewCountOf(
          pages: pages,
          pageMode: pageMode,
          singleFirst: singleFirst,
        ),
      );
    }

    // Spread: two portrait pages flanking the crease. Reading order is
    // preserved; RTL only mirrors which physical room holds which page.
    final spread = _spreadContaining(
      pages: pages,
      anchor: anchor,
      singleFirst: singleFirst,
    );
    final anchorIsSecond = spread.secondIndex == anchor;
    final (leftRoom, rightRoom) = rooms.spreadRooms();
    final Rect primaryRoom;
    final Rect facingRoom;
    if (rtl) {
      // First page on the right, second page on the left.
      primaryRoom = anchorIsSecond ? leftRoom : rightRoom;
      facingRoom = anchorIsSecond ? rightRoom : leftRoom;
    } else {
      primaryRoom = anchorIsSecond ? rightRoom : leftRoom;
      facingRoom = anchorIsSecond ? leftRoom : rightRoom;
    }

    final band = spec.creaseBand;
    final double gutter;
    if (band == null) {
      gutter = 0;
    } else if (rooms.verticalBand) {
      // Vertical band: the physical 32px dead zone separates the rooms
      // (FoldReaderRooms.spreadGutter is the authority).
      gutter = rooms.spreadGutter;
    } else {
      // Horizontal band: pages split the lower room; hairline divider only.
      gutter = hairlineDivider;
    }

    return ReaderSplitPlan(
      mode: ReaderSplitMode.spread,
      primaryRoom: primaryRoom,
      facingRoom: facingRoom,
      creaseBand: band,
      gutter: gutter,
      anchorActualIndex: anchor,
      anchorIsSecond: anchorIsSecond,
      pageViewIndex: _pageViewIndexOf(
        pages: pages,
        pageMode: pageMode,
        anchor: anchor,
        singleFirst: singleFirst,
      ),
      pageViewCount: _pageViewCountOf(
        pages: pages,
        pageMode: pageMode,
        singleFirst: singleFirst,
      ),
    );
  }

  /// Whether [anchor] sits in a two-page spread under doublePage grouping.
  bool _isSpreadable(
    List<UChapDataPreload> pages,
    int anchor,
    bool singleFirst,
  ) => !_spreadContaining(
    pages: pages,
    anchor: anchor,
    singleFirst: singleFirst,
  ).isSingle;

  DoublePageSpread _spreadContaining({
    required List<UChapDataPreload> pages,
    required int anchor,
    required bool singleFirst,
  }) {
    final spreads = ReaderPageIndexMath.buildSpreads(
      pages,
      singleFirst: singleFirst,
    );
    for (final spread in spreads) {
      if (spread.firstIndex == anchor || spread.secondIndex == anchor) {
        return spread;
      }
    }
    return DoublePageSpread(anchor);
  }

  int _pageViewIndexOf({
    required List<UChapDataPreload> pages,
    required PageMode pageMode,
    required int anchor,
    required bool singleFirst,
  }) {
    if (pageMode == PageMode.onePage) return anchor;
    final spreads = ReaderPageIndexMath.buildSpreads(
      pages,
      singleFirst: singleFirst,
    );
    for (var i = 0; i < spreads.length; i++) {
      if (spreads[i].firstIndex == anchor || spreads[i].secondIndex == anchor) {
        return i;
      }
    }
    return anchor.clamp(0, spreads.isEmpty ? 0 : spreads.length - 1);
  }

  int _pageViewCountOf({
    required List<UChapDataPreload> pages,
    required PageMode pageMode,
    required bool singleFirst,
  }) {
    if (pageMode == PageMode.onePage) return pages.length;
    return ReaderPageIndexMath.buildSpreads(
      pages,
      singleFirst: singleFirst,
    ).length;
  }
}
