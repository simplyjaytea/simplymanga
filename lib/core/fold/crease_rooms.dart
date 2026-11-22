import 'package:flutter/widgets.dart';

import 'fold_layout.dart';

/// Reader-room geometry around the physical crease.
///
/// Unlike [FoldTwoRoomLayout] (detail screens, 16pt outer margins), reader
/// rooms are flush with the viewport edges and the crease band: imagery and
/// text fill a whole room and never straddle the band. On postures without a
/// crease the rooms degrade to the legacy full-viewport geometry.
class FoldReaderRooms {
  const FoldReaderRooms({required this.spec, required this.viewport});

  final FoldLayoutSpec spec;
  final Size viewport;

  Rect? get creaseBand => spec.creaseBand;
  bool get hasBand => creaseBand != null;

  /// True when the band runs top-to-bottom (inner portrait / tall half-open).
  bool get verticalBand {
    final band = creaseBand;
    return band != null && band.height >= band.width;
  }

  Rect get fullViewport => Offset.zero & viewport;

  /// Room for a single page. Vertical band: right room for LTR, left for RTL.
  /// Horizontal band: the bottom room (the top room stays empty, matching the
  /// controls-region convention used by the anime player chrome).
  Rect singlePageRoom({required bool rtl}) {
    final band = creaseBand;
    if (band == null) return fullViewport;
    if (verticalBand) {
      return rtl
          ? Rect.fromLTRB(0, 0, band.left, viewport.height)
          : Rect.fromLTRB(band.right, 0, viewport.width, viewport.height);
    }
    return Rect.fromLTRB(0, band.bottom, viewport.width, viewport.height);
  }

  /// Two rooms for a spread, in reading order (left page first for LTR).
  /// Vertical band: one room per side of the band. Horizontal band: the
  /// bottom room split in half, so both pages stay below the crease.
  (Rect, Rect) spreadRooms() {
    final band = creaseBand;
    if (band == null) {
      final half = viewport.width / 2;
      return (
        Rect.fromLTRB(0, 0, half, viewport.height),
        Rect.fromLTRB(half, 0, viewport.width, viewport.height),
      );
    }
    if (verticalBand) {
      return (
        Rect.fromLTRB(0, 0, band.left, viewport.height),
        Rect.fromLTRB(band.right, 0, viewport.width, viewport.height),
      );
    }
    final bottom = Rect.fromLTRB(
      0,
      band.bottom,
      viewport.width,
      viewport.height,
    );
    final half = bottom.width / 2;
    return (
      Rect.fromLTRB(bottom.left, bottom.top, bottom.left + half, bottom.bottom),
      Rect.fromLTRB(bottom.left + half, bottom.top, bottom.right, bottom.bottom),
    );
  }

  /// Gutter between spread pages: the band width for a vertical band, else 0.
  double get spreadGutter => hasBand && verticalBand ? creaseBand!.width : 0;
}

/// Positions [child] inside [room] within a full [viewport]-sized box.
///
/// When the room equals the viewport the widget is layout-identical to the
/// bare child, so non-fold devices keep their existing geometry.
class CreaseRoomBox extends StatelessWidget {
  const CreaseRoomBox({
    super.key,
    required this.viewport,
    required this.room,
    required this.child,
  });

  final Size viewport;
  final Rect room;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (viewport.width <= 0 || viewport.height <= 0) return child;
    // Align maps the child across the *free* space, so derive the alignment
    // from the room's offset within that free space (not its centre share of
    // the viewport). Flush rooms land exactly on the band edges.
    final freeX = viewport.width - room.width;
    final freeY = viewport.height - room.height;
    return SizedBox(
      width: viewport.width,
      height: viewport.height,
      child: Align(
        alignment: Alignment(
          freeX <= 0 ? 0 : ((room.left / freeX) * 2 - 1).clamp(-1.0, 1.0),
          freeY <= 0 ? 0 : ((room.top / freeY) * 2 - 1).clamp(-1.0, 1.0),
        ),
        child: SizedBox(width: room.width, height: room.height, child: child),
      ),
    );
  }
}
