import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// Which display room an overlay was invoked from on a two-room posture.
enum ShioriOverlaySide { left, right }

/// The rooms a modal overlay may present into on a foldable display, in
/// global logical coordinates.
///
/// Shiori stays fold-agnostic: the app resolves these rectangles from its
/// settled fold posture (the same crease law that splits the shell) and
/// publishes them through [ShioriOverlayScope]. With no scope above the
/// route, overlays present exactly as they always have — full display.
@immutable
class ShioriOverlayRooms {
  const ShioriOverlayRooms({
    required this.creaseBand,
    this.leftRoom,
    this.rightRoom,
    this.lowerRoom,
  });

  /// The hinge band the overlay must never render across.
  final Rect creaseBand;

  /// Portrait two-room posture: rooms either side of a vertical crease.
  final Rect? leftRoom;
  final Rect? rightRoom;

  /// Landscape two-room posture: the single room below a horizontal crease.
  final Rect? lowerRoom;

  /// Whether these rooms were computed for a display of [size].
  ///
  /// The crease band is the fingerprint of the display geometry the rooms
  /// were derived from. During a fold the display size changes immediately
  /// while the settled posture (and thus the rooms) arrives one debounce
  /// later; applying stale rooms to the new display would squeeze the
  /// overlay into a sliver. Frames check this and present full-display
  /// until the scope republishes rooms that fit.
  bool fits(Size size) =>
      creaseBand.left >= 0 &&
      creaseBand.top >= 0 &&
      creaseBand.right <= size.width &&
      creaseBand.bottom <= size.height;
}

/// Ambient overlay rooms, installed above the Navigator so every modal
/// route — pushed now or already open — can read them. Rebuilding the scope
/// on a settled posture change re-presents open overlays without touching
/// route identity, so sheet state, scroll offset and field focus survive.
class ShioriOverlayScope extends InheritedWidget {
  const ShioriOverlayScope({
    super.key,
    required this.rooms,
    required super.child,
  });

  /// Null on single-room displays (cover, unknown posture).
  final ShioriOverlayRooms? rooms;

  static ShioriOverlayScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShioriOverlayScope>();

  @override
  bool updateShouldNotify(ShioriOverlayScope oldWidget) =>
      rooms != oldWidget.rooms;
}

/// The room an overlay presents into for the current scope and size. With
/// no scope this is the whole display — the classic, fold-free presentation.
Rect shioriOverlayRoom(ShioriOverlayRooms? rooms, ShioriOverlaySide? side, Size size) {
  final full = Rect.fromLTWH(0, 0, size.width, size.height);
  if (rooms == null || !rooms.fits(size)) return full;
  final Rect room;
  if (rooms.lowerRoom != null) {
    room = rooms.lowerRoom!;
  } else {
    room = (side == ShioriOverlaySide.left ? rooms.leftRoom : rooms.rightRoom) ??
        full;
  }
  return room.intersect(full);
}

/// The room the invoking widget sits in, derived from its centre relative
/// to the crease band. Null on single-room or horizontal-crease postures
/// (no left/right distinction there). Capture it at invocation time so the
/// overlay returns to the room it came from, even if the user folded the
/// device away and back while it was open.
ShioriOverlaySide? shioriInvokedSide(BuildContext context) {
  final rooms = ShioriOverlayScope.maybeOf(context)?.rooms;
  final band = (rooms != null && rooms.fits(MediaQuery.sizeOf(context)))
      ? rooms.creaseBand
      : null;
  if (band == null || band.width >= band.height) return null;
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final centre = box.localToGlobal(box.size.center(Offset.zero));
  return centre.dx < band.center.dx
      ? ShioriOverlaySide.left
      : ShioriOverlaySide.right;
}

/// Docks a sheet into the surviving room of a settled two-room posture.
///
/// Wrap the sheet surface *inside* the modal route: the route keeps its
/// identity and animation, while this frame re-presents the surface into
/// the room on every settled posture change. The widget structure never
/// changes shape, so sheet state, scroll offset and focus survive folds.
/// With no [ShioriOverlayScope] above, this is an inert pass-through.
class ShioriSheetFrame extends StatelessWidget {
  const ShioriSheetFrame({
    super.key,
    required this.child,
    this.invokedSide,
    this.maxHeightFactor = 0.9,
  });

  final Widget child;
  final ShioriOverlaySide? invokedSide;

  /// Mirrors the route's `maxHeightFactor` so the surface never outgrows
  /// the room it docks into.
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final rooms = ShioriOverlayScope.maybeOf(context)?.rooms;
    final size = MediaQuery.sizeOf(context);
    final room = shioriOverlayRoom(rooms, invokedSide, size);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        room.left,
        0,
        size.width - room.right,
        size.height - room.bottom,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: room.width,
            maxHeight: room.height * maxHeightFactor,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Centres a dialog inside the surviving room of a settled two-room
/// posture, and scopes the room bounds down to the dialog's own theme so
/// its card can never outgrow the room. Inert pass-through with no scope.
class ShioriDialogFrame extends StatelessWidget {
  const ShioriDialogFrame({
    super.key,
    required this.child,
    this.invokedSide,
  });

  final Widget child;
  final ShioriOverlaySide? invokedSide;

  @override
  Widget build(BuildContext context) {
    final rooms = ShioriOverlayScope.maybeOf(context)?.rooms;
    final size = MediaQuery.sizeOf(context);
    final room = shioriOverlayRoom(rooms, invokedSide, size);
    final theme = Theme.of(context).dialogTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        room.left,
        room.top,
        size.width - room.right,
        size.height - room.bottom,
      ),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: room.width),
          child: DialogTheme(
            data: (rooms == null || !rooms.fits(size))
                ? theme
                : theme.copyWith(
                    insetPadding: const EdgeInsets.all(ShioriSpace.s16),
                    constraints: BoxConstraints(
                      maxWidth: room.width,
                      maxHeight: room.height,
                    ),
                  ),
            child: child,
          ),
        ),
      ),
    );
  }
}
