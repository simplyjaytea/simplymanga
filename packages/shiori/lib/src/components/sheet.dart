import 'package:material_ui/material_ui.dart';

import '../alphas.dart';
import '../tokens.dart';
import 'overlay.dart';

/// Opens a sheet from the bottom of the screen, in Shiori's shape.
///
/// The sheet sizes to its content up to [maxHeightFactor] of the screen and
/// scrolls past that. [title] adds a header row under the handle.
///
/// With a [ShioriOverlayScope] above the Navigator (the app installs one for
/// foldables), the sheet re-presents into the surviving room on a settled
/// posture change, clears the crease band, and keeps its state, scroll and
/// focus — the route itself is never re-pushed. Without the scope it opens
/// exactly as it always has.
Future<T?> showShioriSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? title,
  double maxHeightFactor = 0.9,
  bool useRootNavigator = true,
}) {
  final tokens = context.shiori;
  final foldAware = ShioriOverlayScope.maybeOf(context) != null;
  final invokedSide = shioriInvokedSide(context);
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(
      top: Radius.circular(ShioriShape.sheet),
    ),
  );
  // shiori: M3 modal-sheet elevation when the theme sets none.
  final elevation = Theme.of(context).bottomSheetTheme.elevation ?? 1.0;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: useRootNavigator,
    useSafeArea: true,
    backgroundColor: foldAware ? Colors.transparent : tokens.color.ink1,
    elevation: foldAware ? 0 : elevation,
    showDragHandle: false,
    shape: shape,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
    ),
    builder: (sheetContext) {
      final sheet = ShioriSheet(title: title, child: builder(sheetContext));
      if (!foldAware) return sheet;
      // The route's Material stays a transparent full-display ground; the
      // surface lives inside the frame, so a settled fold re-presents it
      // into the surviving room without touching route identity.
      return ShioriSheetFrame(
        invokedSide: invokedSide,
        maxHeightFactor: maxHeightFactor,
        child: Material(
          color: tokens.color.ink1,
          elevation: elevation,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: sheet,
        ),
      );
    },
  );
}

/// The inside of a sheet: the handle, an optional title, and the content.
///
/// [showShioriSheet] wraps its builder in this; use it directly only when a
/// sheet is opened some other way.
class ShioriSheet extends StatelessWidget {
  const ShioriSheet({super.key, this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.shiori;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: ShioriSpace.s8),
            child: Container(
              width: 36,
              height: ShioriSpace.s4,
              decoration: BoxDecoration(
                color: tokens.color.fg.withValues(alpha: Alphas.hairline * 2),
                borderRadius: BorderRadius.circular(ShioriShape.pill),
              ),
            ),
          ),
        ),
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ShioriSpace.s16,
              ShioriSpace.s16,
              ShioriSpace.s16,
              ShioriSpace.s8,
            ),
            child: Semantics(
              header: true,
              child: Text(
                title!,
                style: tokens.text.section.copyWith(color: tokens.color.fg),
              ),
            ),
          ),
        Flexible(child: child),
      ],
    );
  }
}
