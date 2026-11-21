import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shiori/shiori.dart';

import 'fold_layout.dart';

/// Overlay rooms for a settled posture, derived from the same crease law as
/// [FoldTwoRoomLayout]: rooms stand 16pt off the hinge band and keep the
/// 16pt outer margins. Portrait crease → left/right rooms; landscape crease
/// → one lower room; single-room postures → null (classic presentation).
///
/// This is the single source of truth for where overlays may present on a
/// foldable: the shell splits by [FoldLayoutSpec.creaseBand], and overlays
/// dock by the very same band, so the two can never disagree.
ShioriOverlayRooms? foldOverlayRooms(FoldLayoutSpec spec, Size size) {
  final band = spec.creaseBand;
  if (!spec.hasTwoRooms || band == null) return null;
  const margin = ShioriSpace.s16;
  const gutter = ShioriSpace.s16;
  if (band.width < band.height) {
    return ShioriOverlayRooms(
      creaseBand: band,
      leftRoom: Rect.fromLTRB(
        margin,
        margin,
        band.left - gutter,
        size.height - margin,
      ),
      rightRoom: Rect.fromLTRB(
        band.right + gutter,
        margin,
        size.width - margin,
        size.height - margin,
      ),
    );
  }
  return ShioriOverlayRooms(
    creaseBand: band,
    lowerRoom: Rect.fromLTRB(
      margin,
      band.bottom + gutter,
      size.width - margin,
      size.height - margin,
    ),
  );
}

/// Publishes [ShioriOverlayScope] above the Navigator (install it in
/// `MaterialApp.builder`, which wraps the Navigator) so every modal route —
/// including sheets and dialogs already open — re-presents into the
/// surviving room when the posture settles.
///
/// Subscribes to the same settled [FoldStateDriver] the shell listens to:
/// re-presentation happens once per settled posture, never per sensor
/// event. Route identity is untouched, so the routed branch underneath
/// never remounts and open overlays keep their state, scroll and focus.
class FoldOverlayScope extends StatefulWidget {
  const FoldOverlayScope({super.key, required this.driver, required this.child});

  final FoldStateDriver driver;
  final Widget child;

  @override
  State<FoldOverlayScope> createState() => _FoldOverlayScopeState();
}

class _FoldOverlayScopeState extends State<FoldOverlayScope> {
  late FoldState _state = widget.driver.currentState;
  StreamSubscription<FoldState>? _sub;
  FoldState? _resolvedFor;
  ShioriOverlayRooms? _rooms;

  void _listen() {
    _sub = widget.driver.states.listen((state) {
      if (state != _state && mounted) setState(() => _state = state);
    });
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(FoldOverlayScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driver != widget.driver) {
      _sub?.cancel();
      _state = widget.driver.currentState;
      _resolvedFor = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rooms resolve once per settled posture, at the size in force when it
    // settles — never per metrics tick. Mid-fold (posture not yet settled)
    // the previous rooms stay published; ShioriOverlayRooms.fits rejects
    // them against the new display, so overlays present full-display until
    // the settle event lands. Resolving per tick would invent a phantom
    // crease on the new display from the stale posture and squeeze open
    // overlays into a phantom room.
    if (_resolvedFor != _state) {
      final size = MediaQuery.sizeOf(context);
      final spec = FoldLayoutSpec.resolve(foldState: _state, size: size);
      _rooms = foldOverlayRooms(spec, size);
      _resolvedFor = _state;
    }
    return ShioriOverlayScope(rooms: _rooms, child: widget.child);
  }
}
