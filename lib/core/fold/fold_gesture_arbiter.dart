import 'package:flutter/scheduler.dart';

import 'fold_transition.dart';

/// The fold/gesture arbitration contract (C1 spec 5.3).
///
/// A fold settle and an in-flight drag/fling/zoom must never both commit
/// motion. The arbiter owns that decision so readers only provide seams.
/// Media-agnostic: nothing here knows about manga, anime or novels.
abstract interface class FoldGestureArbiter {
  /// Applies one settled transition: cancels any in-flight activity (dropping
  /// velocity), commits the anchor once, and restores it once at the
  /// post-frame seam. Never animates.
  void onFoldSettled(FoldTransition transition);

  /// Stops scroll/scale activity immediately, DROPS velocity (no ballistic
  /// carry) and resets transient drag flags. With [keepAnchor] the current
  /// anchor is committed exactly once so the fold restores it.
  void cancelInFlight({required bool keepAnchor});

  /// True while at least one pointer is down on the gesture surface.
  bool get hasActivePointer;
}

/// Default arbitration (C1 spec 5.3):
/// - one fold -> at most one anchor restore and one page change;
/// - a fling at fold becomes a stop, never a slide (velocity is dropped);
/// - pointer-up after a fold throws nothing and leaks no pointer state;
/// - a fresh drag participates normally in the new geometry.
///
/// The reader wires three BuildContext-free seams:
/// - [stopActivity]: end scroll/scale activity WITHOUT ballistic carry
///   (e.g. `controller.jumpTo(current)` / `goIdle()`, never `animateTo`);
/// - [commitAnchor]: capture the current content anchor (page index) once;
/// - [restoreAnchor]: re-apply that anchor under the new geometry once.
///
/// Restore runs at a post-frame seam (injectable for headless tests) and is
/// latest-wins: rapid settles coalesce into a single restore.
class DefaultFoldGestureArbiter implements FoldGestureArbiter {
  DefaultFoldGestureArbiter({
    required this.stopActivity,
    required this.commitAnchor,
    required this.restoreAnchor,
    void Function(void Function() callback)? postFrameScheduler,
  }) : _postFrame = postFrameScheduler ?? _defaultPostFrame;

  /// Ends any scroll/scale activity and drops its velocity. Must be
  /// idempotent; called at most once per cancel.
  final void Function() stopActivity;

  /// Captures the content anchor. Called at most once between restores.
  final void Function() commitAnchor;

  /// Re-applies the committed anchor under the new geometry. Called once per
  /// settled transition at the post-frame seam; must not animate.
  final void Function() restoreAnchor;

  final void Function(void Function() callback) _postFrame;

  final Set<int> _pointers = <int>{};
  bool _activityInFlight = false;
  double _inFlightVelocity = 0;
  bool _dragActive = false;
  bool _committedSinceRestore = false;
  int _restoreToken = 0;
  bool _disposed = false;
  FoldTransition? _lastSettled;

  static void _defaultPostFrame(void Function() callback) {
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) => callback());
    // addPostFrameCallback alone does NOT schedule a frame. When the settle
    // arrives after the rebuild frame (the usual case), the app would be idle
    // and the restore would wait for the next unrelated frame. Ensure a frame
    // is coming; mid-frame this is a no-op and the callback rides the current
    // frame's post-frame phase.
    binding.ensureVisualUpdate();
  }

  /// The most recent settled transition this arbiter applied.
  FoldTransition? get lastSettled => _lastSettled;

  /// True while a scroll/fling/zoom activity is in flight.
  bool get hasInFlightActivity => _activityInFlight;

  /// Velocity of the in-flight activity; always 0 after a cancel/settle.
  double get inFlightVelocity => _inFlightVelocity;

  /// Transient drag flag; reset by cancel so a late pointer-up cannot
  /// re-fire a page turn.
  bool get dragActive => _dragActive;

  @override
  bool get hasActivePointer => _pointers.isNotEmpty;

  /// Registers a pointer-down on the gesture surface.
  void pointerDown(int pointer) {
    if (_disposed) return;
    _pointers.add(pointer);
    _dragActive = true;
  }

  /// Registers a pointer-up/cancel. Tolerates unknown pointers (a pointer
  /// that went down before the fold and up after it must throw nothing).
  void pointerUp(int pointer) {
    if (_disposed) return;
    _pointers.remove(pointer);
    if (_pointers.isEmpty) _dragActive = false;
  }

  /// Marks a scroll/fling/zoom activity as in flight. [velocity] is the
  /// ballistic velocity the reader would otherwise carry; the arbiter drops
  /// it at the fold boundary.
  void markActivityInFlight({double velocity = 0}) {
    if (_disposed) return;
    _activityInFlight = true;
    _inFlightVelocity = velocity;
  }

  /// Marks the activity as naturally finished (no fold involved).
  void markActivityIdle() {
    if (_disposed) return;
    _activityInFlight = false;
    _inFlightVelocity = 0;
  }

  @override
  void onFoldSettled(FoldTransition transition) {
    if (_disposed) return;
    // No double-fire: the same settle delivered twice changes nothing.
    if (_lastSettled != null &&
        (identical(_lastSettled, transition) ||
            _lastSettled == transition)) {
      return;
    }
    _lastSettled = transition;
    if (hasActivePointer || _activityInFlight || _dragActive) {
      cancelInFlight(keepAnchor: true);
    } else if (!_committedSinceRestore) {
      // Resting fold: still commit + restore the anchor exactly once.
      commitAnchor();
      _committedSinceRestore = true;
    }
    _scheduleRestore();
  }

  @override
  void cancelInFlight({required bool keepAnchor}) {
    if (_disposed) return;
    stopActivity(); // seam drops velocity; no ballistic carry survives
    _activityInFlight = false;
    _inFlightVelocity = 0;
    _dragActive = false; // a late pointer-up cannot re-fire a page turn
    if (keepAnchor && !_committedSinceRestore) {
      commitAnchor();
      _committedSinceRestore = true;
    }
  }

  /// Invalidates pending restores and ignores further events.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _restoreToken++;
    _pointers.clear();
  }

  void _scheduleRestore() {
    final token = ++_restoreToken;
    _postFrame(() {
      if (_disposed || token != _restoreToken) return;
      _committedSinceRestore = false;
      restoreAnchor();
    });
  }
}
