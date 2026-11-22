import 'dart:async';

import 'package:flutter/widgets.dart';

import 'fold_layout.dart';

/// One settled posture change, with both endpoints (C1 spec 6.2A).
///
/// Emitted exactly once per settled change (`previous != next`), never on
/// live metrics ticks. [previousSize] is the last live viewport size observed
/// under [previous]; [nextSize] is the first live size observed under [next].
/// This is the one event where expensive reflow (page-mode conversion, spread
/// regrouping, zoom remap, re-pagination, anchor restore) is allowed.
class FoldTransition {
  const FoldTransition({
    required this.previous,
    required this.next,
    required this.previousSize,
    required this.nextSize,
    required this.settledAt,
  });

  final FoldState previous;
  final FoldState next;
  final Size previousSize;
  final Size nextSize;
  final DateTime settledAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoldTransition &&
          previous == other.previous &&
          next == other.next &&
          previousSize == other.previousSize &&
          nextSize == other.nextSize &&
          settledAt == other.settledAt;

  @override
  int get hashCode =>
      Object.hash(previous, next, previousSize, nextSize, settledAt);

  @override
  String toString() =>
      'FoldTransition($previous -> $next, $previousSize -> $nextSize)';
}

/// The settled-transition seam: a broadcast stream plus the last transition.
///
/// Owned by [FoldStateController] and exposed through [FoldLayoutScope] so
/// readers (and later the player) share one hook without media imports.
/// Media-agnostic: nothing here knows about manga, anime or novels.
class FoldTransitionController {
  final StreamController<FoldTransition> _transitions =
      StreamController<FoldTransition>.broadcast();
  FoldTransition? _lastTransition;
  bool _disposed = false;

  /// The most recent settled transition, or null before the first settle.
  FoldTransition? get lastTransition => _lastTransition;

  /// One event per settled change; never fires for live metrics ticks.
  Stream<FoldTransition> get transitions => _transitions.stream;

  /// Publishes a settled transition. Called by the fold shell machinery,
  /// not by readers.
  void notify(FoldTransition transition) {
    if (_disposed) return;
    _lastTransition = transition;
    _transitions.add(transition);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_transitions.close());
  }
}
