import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'package:mangayomi/core/fold/fold_layout.dart';

/// F-1 / D-6: a grid delegate that treats the unfolded inner display as two
/// pages. When a vertical crease band is supplied, columns are laid out as an
/// EVEN number per room with a gutter over the band, so no cover is ever
/// bisected by the spine. Without a band the geometry is identical to the
/// stock delegates (cover, TV and non-foldables keep their existing grids).
///
/// Pure layout: reads only the band and the sizing rules, never a media type
/// or a device model.
class FoldGridDelegate extends SliverGridDelegate {
  const FoldGridDelegate({
    this.fixedCrossAxisCount,
    this.maxCrossAxisExtent,
    required this.childAspectRatio,
    this.crossAxisSpacing = 0,
    this.mainAxisSpacing = 0,
    this.creaseBand,
    this.forceEvenColumns = false,
  }) : assert(
         (fixedCrossAxisCount == null) != (maxCrossAxisExtent == null),
         'Supply exactly one of fixedCrossAxisCount / maxCrossAxisExtent',
       ),
       assert(fixedCrossAxisCount == null || fixedCrossAxisCount > 0),
       assert(maxCrossAxisExtent == null || maxCrossAxisExtent > 0),
       assert(childAspectRatio > 0),
       assert(crossAxisSpacing >= 0),
       assert(mainAxisSpacing >= 0);

  /// User-pinned column count (the library grid-size setting). On inner an
  /// odd count is rounded up so both rooms stay balanced; off inner it is
  /// honoured exactly, as before.
  final int? fixedCrossAxisCount;

  /// Width-derived column budget, as the stock max-extent delegate uses.
  final double? maxCrossAxisExtent;

  final double childAspectRatio;
  final double crossAxisSpacing;
  final double mainAxisSpacing;

  /// The vertical crease band in sliver-local coordinates (the caller shifts
  /// it by the grid's horizontal padding). Null off inner, or when the band
  /// runs horizontally (inner landscape has no spine to bisect columns).
  final Rect? creaseBand;

  /// D-6 "never odd on inner": round an odd width-derived column count up to
  /// even even when no vertical gutter applies (inner landscape).
  final bool forceEvenColumns;

  /// The geometry for a grid of [crossAxisExtent] logical pixels width.
  FoldGridLayout geometryFor(double crossAxisExtent) {
    final band = creaseBand;
    if (band != null && band.height > band.width && band.width > 0) {
      // Two rooms, one gutter centred on the band, widened to the full
      // 32pt crease allowance. Rooms are measured from the sliver edges so
      // the grid stays edge-to-edge exactly like the cover grid.
      final gutterWidth = math.max(band.width, FoldLayoutSpec.creaseBandWidth);
      final center = band.center.dx.clamp(
        gutterWidth / 2,
        math.max(gutterWidth / 2, crossAxisExtent - gutterWidth / 2),
      );
      final gutterStart = center - gutterWidth / 2;
      final gutterEnd = center + gutterWidth / 2;
      final leftRoom = gutterStart;
      final rightRoom = crossAxisExtent - gutterEnd;
      final perRoom = fixedCrossAxisCount != null
          ? math.max(1, (fixedCrossAxisCount! / 2).ceil())
          : math.max(
              1,
              (math.max(leftRoom, rightRoom) / maxCrossAxisExtent!).ceil(),
            );
      final leftTileWidth = math.max(
        0.0,
        (leftRoom - (perRoom - 1) * crossAxisSpacing) / perRoom,
      );
      final rightTileWidth = math.max(
        0.0,
        (rightRoom - (perRoom - 1) * crossAxisSpacing) / perRoom,
      );
      // One row height for both rooms keeps rows aligned across the spine;
      // with a centred band the rooms are equal anyway.
      final tileHeight =
          math.max(leftTileWidth, rightTileWidth) / childAspectRatio;
      return FoldGridLayout(
        crossAxisExtent: crossAxisExtent,
        columns: perRoom * 2,
        leftColumns: perRoom,
        gutterStart: gutterStart,
        gutterEnd: gutterEnd,
        leftTileWidth: leftTileWidth,
        rightTileWidth: rightTileWidth,
        tileHeight: tileHeight,
        crossAxisSpacing: crossAxisSpacing,
        mainAxisSpacing: mainAxisSpacing,
        reverseCrossAxis: false,
      );
    }
    // No vertical band: the legacy rules, verbatim.
    var columns =
        fixedCrossAxisCount ??
        math.max(1, (crossAxisExtent / maxCrossAxisExtent!).ceil());
    if (forceEvenColumns && columns.isOdd) columns += 1;
    final tileWidth = math.max(
      0.0,
      (crossAxisExtent - (columns - 1) * crossAxisSpacing) / columns,
    );
    return FoldGridLayout(
      crossAxisExtent: crossAxisExtent,
      columns: columns,
      leftColumns: columns,
      gutterStart: 0,
      gutterEnd: 0,
      leftTileWidth: tileWidth,
      rightTileWidth: tileWidth,
      tileHeight: tileWidth / childAspectRatio,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      reverseCrossAxis: false,
    );
  }

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final layout = geometryFor(constraints.crossAxisExtent);
    return layout._reversed(axisDirectionIsReversed(constraints.crossAxisDirection));
  }

  @override
  bool shouldRelayout(FoldGridDelegate oldDelegate) {
    return oldDelegate.fixedCrossAxisCount != fixedCrossAxisCount ||
        oldDelegate.maxCrossAxisExtent != maxCrossAxisExtent ||
        oldDelegate.childAspectRatio != childAspectRatio ||
        oldDelegate.crossAxisSpacing != crossAxisSpacing ||
        oldDelegate.mainAxisSpacing != mainAxisSpacing ||
        oldDelegate.creaseBand != creaseBand ||
        oldDelegate.forceEvenColumns != forceEvenColumns;
  }
}

/// The tile geometry produced by [FoldGridDelegate]: uniform rows, an even
/// column count, and (on inner portrait) a gutter that no tile may enter.
/// Exposed so tests and scroll anchoring can ask where a cell lives without
/// building a widget tree.
class FoldGridLayout extends SliverGridLayout {
  const FoldGridLayout({
    required this.crossAxisExtent,
    required this.columns,
    required this.leftColumns,
    required this.gutterStart,
    required this.gutterEnd,
    required this.leftTileWidth,
    required this.rightTileWidth,
    required this.tileHeight,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.reverseCrossAxis,
  }) : assert(columns > 0),
       assert(leftColumns > 0 && leftColumns <= columns),
       assert(tileHeight >= 0);

  final double crossAxisExtent;

  /// Total columns per row. Even whenever a crease band or
  /// [FoldGridDelegate.forceEvenColumns] applies.
  final int columns;

  /// Columns in the left room; the rest sit right of the gutter.
  final int leftColumns;

  /// Gutter edges in sliver-local cross-axis coordinates; both zero when no
  /// band applies.
  final double gutterStart;
  final double gutterEnd;

  final double leftTileWidth;
  final double rightTileWidth;
  final double tileHeight;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final bool reverseCrossAxis;

  double get rowStride => tileHeight + mainAxisSpacing;

  double rowTop(int row) => row * rowStride;

  /// The row that contains [index].
  int rowOf(int index) => index ~/ columns;

  /// The first row whose tiles may still be visible at [scrollOffset].
  int rowForScrollOffset(double scrollOffset) {
    if (rowStride <= precisionErrorTolerance) return 0;
    return math.max(0, scrollOffset ~/ rowStride);
  }

  /// The full cell rect in sliver-local coordinates (cross axis = x, main
  /// axis = y), before any reverse-cross-axis mirroring.
  Rect cellRect(int index) {
    final (left, width) = _columnSpan(index % columns);
    return Rect.fromLTWH(left, rowTop(rowOf(index)), width, tileHeight);
  }

  /// Column origin and tile width, kept as stored values: round-tripping
  /// through Rect.right - Rect.left would lose a ULP against the stock
  /// delegates' geometry.
  (double, double) _columnSpan(int column) {
    if (column < leftColumns) {
      return (column * (leftTileWidth + crossAxisSpacing), leftTileWidth);
    }
    return (
      gutterEnd + (column - leftColumns) * (rightTileWidth + crossAxisSpacing),
      rightTileWidth,
    );
  }

  FoldGridLayout _reversed(bool reverse) {
    if (reverse == reverseCrossAxis) return this;
    return FoldGridLayout(
      crossAxisExtent: crossAxisExtent,
      columns: columns,
      leftColumns: leftColumns,
      gutterStart: gutterStart,
      gutterEnd: gutterEnd,
      leftTileWidth: leftTileWidth,
      rightTileWidth: rightTileWidth,
      tileHeight: tileHeight,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      reverseCrossAxis: reverse,
    );
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    final (left, width) = _columnSpan(index % columns);
    return SliverGridGeometry(
      scrollOffset: rowTop(rowOf(index)),
      crossAxisOffset: reverseCrossAxis
          ? crossAxisExtent - left - width
          : left,
      mainAxisExtent: tileHeight,
      crossAxisExtent: width,
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    if (childCount == 0) return 0;
    final rows = (childCount / columns).ceil();
    return math.max(0.0, rowStride * rows - mainAxisSpacing);
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    return columns * rowForScrollOffset(scrollOffset);
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    if (rowStride <= 0) return 0;
    final rows = (scrollOffset / rowStride).ceil();
    return math.max(0, columns * rows - 1);
  }
}