import 'dart:async';

import 'package:flutter/widgets.dart';

import 'fold_gesture_arbiter.dart';
import 'fold_layout.dart';
import 'fold_transition.dart';

/// The fold/gesture boundary (C1 spec 5.3): placed inside [FoldAwareShell],
/// above the reader's gesture surface.
///
/// Subscribes to the shell's [FoldTransitionController] and forwards each
/// settled transition to the arbiter exactly once. Pointer down/up/cancel on
/// the surface below are tracked so the arbiter can distinguish a fold
/// mid-drag from a resting fold, and a late pointer-up after a fold leaks
/// nothing.
///
/// BuildContext-free seam: the reader constructs a [DefaultFoldGestureArbiter]
/// with closures over its own scroll/zoom controllers and passes it here;
/// this widget never touches those controllers itself. Media-agnostic.
///
/// Pointer tracking is forwarded only to [DefaultFoldGestureArbiter]: the
/// spec-fixed three-member [FoldGestureArbiter] interface has no pointer
/// members, so a custom implementation receives settled transitions but no
/// raw pointer events. Extending the interface for custom pointer handling
/// is a follow-up; until then `hasActivePointer` on a custom arbiter is its
/// own responsibility.
class FoldGestureBoundary extends StatefulWidget {
  const FoldGestureBoundary({
    super.key,
    required this.arbiter,
    required this.child,
  });

  final FoldGestureArbiter arbiter;
  final Widget child;

  @override
  State<FoldGestureBoundary> createState() => _FoldGestureBoundaryState();
}

class _FoldGestureBoundaryState extends State<FoldGestureBoundary> {
  FoldTransitionController? _controller;
  StreamSubscription<FoldTransition>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = FoldLayoutScope.maybeOf(context)?.transitions;
    if (controller != _controller) {
      _subscription?.cancel();
      _controller = controller;
      _subscription = controller?.transitions.listen(_onSettled);
    }
  }

  void _onSettled(FoldTransition transition) {
    if (!mounted) return;
    widget.arbiter.onFoldSettled(transition);
  }

  void _pointerDown(PointerDownEvent event) {
    final arbiter = widget.arbiter;
    if (arbiter is DefaultFoldGestureArbiter) {
      arbiter.pointerDown(event.pointer);
    }
  }

  void _pointerUp(PointerUpEvent event) {
    final arbiter = widget.arbiter;
    if (arbiter is DefaultFoldGestureArbiter) {
      arbiter.pointerUp(event.pointer);
    }
  }

  void _pointerCancel(PointerCancelEvent event) {
    final arbiter = widget.arbiter;
    if (arbiter is DefaultFoldGestureArbiter) {
      arbiter.pointerUp(event.pointer);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerCancel,
      child: widget.child,
    );
  }
}
