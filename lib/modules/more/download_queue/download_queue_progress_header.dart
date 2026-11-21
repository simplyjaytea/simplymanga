import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/core/fold/fold_layout.dart';
import 'package:mangayomi/services/download_manager/download_queue_progress.dart';
import 'package:shiori/shiori.dart';

/// Aggregate progress for the download queue, shown above the queue list.
///
/// On the inner portrait display the two rooms either side of the hinge are
/// used deliberately: the active/waiting counts sit in the left room and the
/// overall bar with its percent readout in the right, each inset a gutter from
/// the crease band so nothing is painted across the hinge. Every other posture
/// (cover, cover landscape, inner landscape) gets one compact row; on inner
/// landscape that row stays above the horizontal crease.
///
/// The header reads the settled [FoldLayoutSpec] from the nearest
/// [FoldLayoutScope] (provided by [FoldAwareShell], which debounces the posture
/// stream). Outside a fold shell it falls back to a compact row, so it also
/// works on ordinary screens.
class DownloadQueueProgressHeader extends StatelessWidget {
  const DownloadQueueProgressHeader({
    super.key,
    required this.progress,
    this.semanticLabel,
  });

  final DownloadQueueProgress progress;

  /// Optional accessibility label for the whole header.
  final String? semanticLabel;

  static const double _margin = ShioriSpace.s16;

  @override
  Widget build(BuildContext context) {
    if (progress.isEmpty) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    final spec =
        FoldLayoutScope.maybeOf(context)?.spec ??
        FoldLayoutSpec.resolve(foldState: FoldState.unknown, size: size);
    final band = spec.creaseBand;

    Widget content;
    if (spec.foldState == FoldState.innerPortrait && band != null) {
      content = _splitRooms(context, size, band);
    } else {
      content = _compactRow(context, size);
    }
    if (semanticLabel != null) {
      content = Semantics(
        label: semanticLabel,
        container: true,
        child: content,
      );
    }
    return content;
  }

  /// Inner portrait: counts in the left room, bar + percent in the right, with
  /// the crease band and a gutter on each side left empty between them.
  Widget _splitRooms(BuildContext context, Size size, Rect band) {
    final tokens = context.shiori;
    final leftWidth = band.left - _margin - _margin;
    final rightLeft = band.right + _margin;
    final rightWidth = size.width - _margin - rightLeft;
    return SizedBox(
      width: size.width,
      height: tokens.density.rowHeight,
      child: Stack(
        children: [
          Positioned(
            left: _margin,
            top: 0,
            bottom: 0,
            width: leftWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _counts(context),
            ),
          ),
          Positioned(
            left: rightLeft,
            top: 0,
            bottom: 0,
            width: rightWidth,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _barWithPercent(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactRow(BuildContext context, Size size) {
    final tokens = context.shiori;
    return SizedBox(
      width: size.width,
      height: tokens.density.rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _margin),
        child: Row(
          spacing: ShioriSpace.s12,
          children: [
            _counts(context),
            Expanded(child: _barWithPercent(context)),
          ],
        ),
      ),
    );
  }

  Widget _counts(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    if (progress.paused) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: ShioriSpace.s8,
        children: [
          const Icon(Symbols.pause, size: 18, fill: 1),
          Text('Paused', style: label),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: ShioriSpace.s8,
      children: [
        const Icon(Symbols.downloading, size: 18, fill: 1),
        Text('${progress.activeCount}', style: label),
        const Icon(Symbols.hourglass_empty, size: 18, fill: 1),
        Text('${progress.waitingCount}', style: label),
      ],
    );
  }

  Widget _barWithPercent(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    return Row(
      spacing: ShioriSpace.s8,
      children: [
        Expanded(child: ShioriProgressBar(value: progress.overallFraction)),
        Text('${progress.percent}%', style: label),
      ],
    );
  }
}
