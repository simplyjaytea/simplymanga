import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';
import 'package:mangayomi/core/fold/fold_grid_delegate.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/utils/platform_utils.dart';

/// The shared cover grid. On a two-room inner display it becomes two pages:
/// an even column count per room with a gutter over the crease, so no cover
/// is ever bisected (F-1 / D-6). Everywhere else — cover, TV, non-foldables —
/// the geometry is exactly the legacy width-derived / fixed-count grid.
///
/// When the column layout changes across a fold, the first-visible cover is
/// kept under the thumb: its row is re-anchored so the same item stays at the
/// same viewport position (scroll continuity, <= 8pt).
class GridViewWidget extends StatefulWidget {
  final ScrollController? controller;
  final int? itemCount;
  final bool reverse;
  final double? childAspectRatio;
  final Widget? Function(BuildContext, int) itemBuilder;
  final int? gridSize;
  const GridViewWidget({
    super.key,
    this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.reverse = false,
    this.childAspectRatio = 0.69,
    this.gridSize,
  });

  @override
  State<GridViewWidget> createState() => _GridViewWidgetState();
}

class _GridViewWidgetState extends State<GridViewWidget> {
  FoldGridDelegate? _lastDelegate;
  FoldGridLayout? _lastGeometry;
  double? _lastWidth;

  /// The cover currently pinned under the thumb, its viewport position, and
  /// the scroll offset that puts it there. A fold can re-column in several
  /// hops (the viewport resizes before the posture settles); carrying the
  /// anchor across hops keeps the SAME cover pinned instead of re-snapping
  /// to a new row start each hop. Reused only while the scroll offset still
  /// matches — a user scroll invalidates it and the next change re-anchors
  /// from whatever is first visible then.
  ({int index, double viewportY, double expectedPixels})? _pendingAnchor;

  ScrollController? _resolveController() {
    if (widget.controller != null) return widget.controller;
    // Mirrors ScrollView's primary-controller resolution: the library grid
    // passes no controller and rides the route's primary one.
    if (PrimaryScrollController.shouldInherit(context, Axis.vertical)) {
      return PrimaryScrollController.maybeOf(context);
    }
    return null;
  }

  /// When the grid re-columns (fold settle, grid-size change), keep the
  /// first-visible cover at the same viewport position instead of letting
  /// the raw scroll offset point at a different row.
  void _captureAnchor(
    FoldGridDelegate delegate,
    double width,
    double paddingTop,
  ) {
    final geometry = delegate.geometryFor(width);
    final previous = _lastGeometry;
    final previousDelegate = _lastDelegate;
    final changed =
        previousDelegate == null ||
        delegate.shouldRelayout(previousDelegate) ||
        width != _lastWidth;
    _lastDelegate = delegate;
    _lastGeometry = geometry;
    _lastWidth = width;
    if (previous == null || !changed) return;

    final controller = _resolveController();
    if (controller == null || !controller.hasClients) return;
    final pixels = controller.position.pixels;
    final itemCount = widget.itemCount;
    int anchorIndex;
    double anchorViewportY;
    final pending = _pendingAnchor;
    if (pending != null &&
        (pixels - pending.expectedPixels).abs() < 0.5 &&
        (itemCount == null || pending.index < itemCount)) {
      anchorIndex = pending.index;
      anchorViewportY = pending.viewportY;
    } else {
      final oldRow = previous.rowForScrollOffset(pixels - paddingTop);
      anchorIndex = oldRow * previous.columns;
      if (itemCount != null && anchorIndex >= itemCount) {
        _pendingAnchor = null;
        return;
      }
      anchorViewportY = paddingTop + previous.rowTop(oldRow) - pixels;
    }
    final newRow = anchorIndex ~/ geometry.columns;
    final rawTarget =
        paddingTop + geometry.rowTop(newRow) - anchorViewportY;
    _pendingAnchor = (
      index: anchorIndex,
      viewportY: anchorViewportY,
      expectedPixels: rawTarget,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final liveController = _resolveController();
      if (liveController == null || !liveController.hasClients) return;
      final position = liveController.position;
      final target = rawTarget.clamp(0.0, position.maxScrollExtent);
      final still = _pendingAnchor;
      if (still != null && still.index == anchorIndex) {
        _pendingAnchor = (
          index: still.index,
          viewportY: still.viewportY,
          expectedPixels: target,
        );
      }
      if ((target - position.pixels).abs() > 0.5) {
        position.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final spec = FoldLayoutScope.maybeOf(context)?.spec;
    final padding =
        (isTv
                ? const EdgeInsets.fromLTRB(
                    ShioriSpace.s12,
                    ShioriSpace.s12,
                    ShioriSpace.s12,
                    ShioriSpace.s12,
                  )
                : const EdgeInsets.only(top: ShioriSpace.s12))
            .add(pageBottomInsets(context))
            .resolve(TextDirection.ltr);
    final foldAware = !isTv && spec != null && spec.hasTwoRooms;
    final band = foldAware ? spec.creaseBand : null;
    // Only a vertical band can bisect columns; the band arrives in
    // window-local coordinates, so shift it into the grid's own frame.
    final verticalBand = (band != null && band.height > band.width)
        ? band.shift(Offset(-padding.left, 0))
        : null;
    final delegate = widget.gridSize == null || widget.gridSize == 0
        ? FoldGridDelegate(
            childAspectRatio: widget.childAspectRatio!,
            // Denser default on TV: from across a room 220px covers show
            // only ~4 huge tiles; 150 gives more, smaller covers.
            maxCrossAxisExtent: isTv ? 150 : 220,
            crossAxisSpacing: isTv ? 10 : 0,
            mainAxisSpacing: isTv ? 10 : 0,
            creaseBand: verticalBand,
            forceEvenColumns: foldAware,
          )
        : FoldGridDelegate(
            fixedCrossAxisCount: widget.gridSize!,
            childAspectRatio: widget.childAspectRatio!,
            crossAxisSpacing: isTv ? 10 : 0,
            mainAxisSpacing: isTv ? 10 : 0,
            creaseBand: verticalBand,
            forceEvenColumns: foldAware,
          );
    return Container(
      color: context.shiori.color.ink0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _captureAnchor(
            delegate,
            constraints.maxWidth - padding.horizontal,
            padding.top,
          );
          return GridView.builder(
            // Grid spacing defaults to zero, so covers sat flush against each
            // other and the grid ran to the screen edges. On TV the focused
            // cover scales up, and with no gap it had nowhere to grow: give it
            // room, and keep the edge columns off the panel edge.
            padding: padding,
            controller: widget.controller,
            gridDelegate: delegate,
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder,
          );
        },
      ),
    );
  }
}