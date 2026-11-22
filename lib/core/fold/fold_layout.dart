import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shiori/shiori.dart';

import 'fold_transition.dart';

/// Settled display postures reported by the platform fold channel.
///
/// The metrics fallback must report [cover] or [halfOpen] only when it has
/// enough evidence. The OS fold animation itself is never reproduced here.
enum FoldState { unknown, cover, innerPortrait, innerLandscape, halfOpen }

enum FoldDensity { compact, inner }

/// An injectable boundary between platform posture events and Flutter layout.
abstract interface class FoldStateDriver {
  FoldState get currentState;
  Stream<FoldState> get states;
}

/// Debounces noisy platform metrics; only the most recent posture is emitted.
///
/// B0's native adapter can call [report] for every metrics event. This class
/// performs one settled update after the debounce window, not one rebuild per
/// animation frame.
class FoldStateController implements FoldStateDriver {
  FoldStateController({
    FoldState initialState = FoldState.unknown,
    this.debounce = const Duration(milliseconds: 120),
  }) : _currentState = initialState;

  final Duration debounce;
  final StreamController<FoldState> _states =
      StreamController<FoldState>.broadcast();
  final FoldTransitionController _transitions = FoldTransitionController();
  Timer? _settleTimer;
  FoldState _currentState;
  bool _disposed = false;

  /// Last live viewport size reported by the shell (every metrics tick).
  Size _liveSize = Size.zero;

  /// A settled change waiting for the settle frame's live size reports.
  FoldState? _pendingPrevious;
  Size _pendingPreviousSize = Size.zero;
  Size? _pendingNextSize;
  bool _completionScheduled = false;

  @override
  FoldState get currentState => _currentState;

  @override
  Stream<FoldState> get states => _states.stream;

  /// The settled-transition seam (C1 spec 6.2A): one [FoldTransition] per
  /// settled change, never per live tick. Exposed through [FoldLayoutScope].
  FoldTransitionController get transitions => _transitions;

  void report(FoldState state) {
    if (_disposed) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(debounce, () => _settle(state));
  }

  /// Reports the live viewport size. Cheap; called on every layout tick.
  ///
  /// Completion of a pending settled transition is deferred to a microtask
  /// so every shell reporting in the same post-frame batch contributes
  /// first: the LAST report wins. In the production nested topology
  /// (root shell + reader shell sharing this controller) the innermost
  /// shell reports last, so both transition endpoints come from one
  /// viewport source instead of mixing the outer shell's nextSize with the
  /// inner shell's previousSize.
  void reportSize(Size size) {
    if (_disposed) return;
    _liveSize = size;
    if (_pendingPrevious != null) {
      _pendingNextSize = size;
      if (!_completionScheduled) {
        _completionScheduled = true;
        scheduleMicrotask(_completePendingTransition);
      }
    }
  }

  void _completePendingTransition() {
    _completionScheduled = false;
    if (_disposed) return;
    final previous = _pendingPrevious;
    final nextSize = _pendingNextSize;
    _pendingPrevious = null;
    _pendingNextSize = null;
    if (previous == null || nextSize == null) return;
    _transitions.notify(
      FoldTransition(
        previous: previous,
        next: _currentState,
        previousSize: _pendingPreviousSize,
        nextSize: nextSize,
        settledAt: DateTime.now(),
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _settleTimer?.cancel();
    _transitions.dispose();
    unawaited(_states.close());
  }

  void _settle(FoldState state) {
    if (_disposed || state == _currentState) return;
    // A previous settle that never saw a live size report (headless use)
    // still emits exactly once, with the best-known size as its endpoint.
    final stalePrevious = _pendingPrevious;
    if (stalePrevious != null) {
      _pendingPrevious = null;
      _pendingNextSize = null;
      _transitions.notify(
        FoldTransition(
          previous: stalePrevious,
          next: _currentState,
          previousSize: _pendingPreviousSize,
          nextSize: _liveSize,
          settledAt: DateTime.now(),
        ),
      );
    }
    _pendingPrevious = _currentState;
    _pendingPreviousSize = _liveSize;
    _currentState = state;
    _states.add(state);
  }
}

/// Headless driver for widget tests and previews. Updates immediately so tests
/// can pump a posture change without a platform channel or wall-clock delay.
class FakeFoldStateDriver extends FoldStateController {
  FakeFoldStateDriver(FoldState initialState)
    : super(initialState: initialState, debounce: Duration.zero);

  @override
  void report(FoldState state) {
    if (state == currentState) return;
    // A zero-duration timer keeps the same event contract while remaining
    // deterministic under WidgetTester.pump().
    super.report(state);
  }
}

/// Geometry and density derived from a settled posture and live viewport size.
class FoldLayoutSpec {
  const FoldLayoutSpec({
    required this.foldState,
    required this.density,
    required this.hasTwoRooms,
    required this.usesTwoPaneDetail,
    required this.creaseBand,
    required this.controlsRegion,
  });

  static const double creaseBandWidth = 32;

  final FoldState foldState;
  final FoldDensity density;
  final bool hasTwoRooms;
  final bool usesTwoPaneDetail;
  final Rect? creaseBand;
  final Rect? controlsRegion;

  factory FoldLayoutSpec.resolve({
    required FoldState foldState,
    required Size size,
  }) {
    final isInner =
        foldState == FoldState.innerPortrait ||
        foldState == FoldState.innerLandscape ||
        foldState == FoldState.halfOpen;
    Rect? band;
    Rect? controls;
    if (foldState == FoldState.innerPortrait) {
      final center = size.width / 2;
      band = Rect.fromLTRB(
        center - creaseBandWidth / 2,
        0,
        center + creaseBandWidth / 2,
        size.height,
      );
    } else if (foldState == FoldState.innerLandscape) {
      final center = size.height / 2;
      band = Rect.fromLTRB(
        0,
        center - creaseBandWidth / 2,
        size.width,
        center + creaseBandWidth / 2,
      );
      controls = Rect.fromLTRB(
        0,
        band.bottom + ShioriSpace.s16,
        size.width,
        size.height,
      );
    } else if (foldState == FoldState.halfOpen) {
      // Posture details are not available on every platform. A metrics-only
      // caller should prefer a regular inner state unless it can observe this.
      if (size.height >= size.width) {
        final center = size.width / 2;
        band = Rect.fromLTRB(
          center - creaseBandWidth / 2,
          0,
          center + creaseBandWidth / 2,
          size.height,
        );
      } else {
        final center = size.height / 2;
        band = Rect.fromLTRB(
          0,
          center - creaseBandWidth / 2,
          size.width,
          center + creaseBandWidth / 2,
        );
        controls = Rect.fromLTRB(
          0,
          band.bottom + ShioriSpace.s16,
          size.width,
          size.height,
        );
      }
    }
    return FoldLayoutSpec(
      foldState: foldState,
      density:
          isInner ||
              (foldState == FoldState.unknown && size.shortestSide >= 600)
          ? FoldDensity.inner
          : FoldDensity.compact,
      hasTwoRooms: isInner,
      usesTwoPaneDetail:
          foldState == FoldState.innerPortrait ||
          (foldState == FoldState.unknown && size.shortestSide >= 600),
      creaseBand: band,
      controlsRegion: controls,
    );
  }
}

/// The shell keeps the routed child at the same element-tree position while
/// exposing the settled layout contract to screens that need room geometry.
///
/// C1 seam (spec 6.2A): the shell also feeds live viewport sizes to the
/// controller and forwards each settled [FoldTransition] to [onSettled] —
/// the one place readers may run expensive reflow. Delivery is post-frame so
/// listeners never run during build.
class FoldAwareShell extends StatefulWidget {
  const FoldAwareShell({
    super.key,
    required this.driver,
    required this.child,
    this.onSettled,
  });

  final FoldStateDriver driver;
  final Widget child;

  /// Called exactly once per settled posture change (previous != next),
  /// never on live metrics ticks. Optional; media-agnostic.
  final void Function(FoldTransition transition)? onSettled;

  @override
  State<FoldAwareShell> createState() => _FoldAwareShellState();
}

class _FoldAwareShellState extends State<FoldAwareShell> {
  late FoldState _foldState = widget.driver.currentState;
  StreamSubscription<FoldState>? _subscription;
  StreamSubscription<FoldTransition>? _transitionSubscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant FoldAwareShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driver != widget.driver) {
      _subscription?.cancel();
      _transitionSubscription?.cancel();
      _foldState = widget.driver.currentState;
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.driver.states.listen((state) {
      if (mounted) setState(() => _foldState = state);
    });
    final driver = widget.driver;
    if (driver is FoldStateController) {
      _transitionSubscription = driver.transitions.transitions.listen((
        transition,
      ) {
        if (!mounted) return;
        widget.onSettled?.call(transition);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _transitionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final spec = FoldLayoutSpec.resolve(foldState: _foldState, size: size);
        final driver = widget.driver;
        if (driver is FoldStateController) {
          // Live size feeds the settled-transition endpoints. Delivered
          // post-frame so onSettled listeners never run during build; the
          // last report in the settle frame's batch completes its
          // FoldTransition (innermost shell wins when shells nest).
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) driver.reportSize(size);
          });
        }
        return FoldLayoutScope(
          spec: spec,
          transitions: driver is FoldStateController
              ? driver.transitions
              : null,
          child: KeyedSubtree(
            key: const ValueKey('fold-aware-routed-content'),
            child: widget.child,
          ),
        );
      },
    );
  }
}

class FoldLayoutScope extends InheritedWidget {
  const FoldLayoutScope({
    super.key,
    required this.spec,
    required super.child,
    this.transitions,
  });

  final FoldLayoutSpec spec;

  /// The settled-transition seam (C1 spec 6.2A), when the shell's driver is
  /// a [FoldStateController]. Null for bare scopes built without a shell.
  final FoldTransitionController? transitions;

  static FoldLayoutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FoldLayoutScope>();

  static FoldLayoutSpec of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'FoldLayoutScope is missing above this context');
    return scope!.spec;
  }

  @override
  bool updateShouldNotify(FoldLayoutScope oldWidget) =>
      spec.foldState != oldWidget.spec.foldState ||
      spec.creaseBand != oldWidget.spec.creaseBand ||
      spec.density != oldWidget.spec.density ||
      spec.usesTwoPaneDetail != oldWidget.spec.usesTwoPaneDetail ||
      transitions != oldWidget.transitions;
}

/// Positions two detail rooms without changing their element-tree parents.
/// Cover keeps one column; inner portrait splits left/right; inner landscape
/// and book posture stack the rooms around the horizontal crease.
class FoldTwoRoomLayout extends StatelessWidget {
  const FoldTwoRoomLayout({
    super.key,
    required this.firstRoom,
    required this.secondRoom,
  });

  final Widget firstRoom;
  final Widget secondRoom;

  @override
  Widget build(BuildContext context) {
    final spec = FoldLayoutScope.of(context);
    return CustomMultiChildLayout(
      delegate: _FoldTwoRoomDelegate(spec.foldState),
      children: [
        LayoutId(id: 0, child: firstRoom),
        LayoutId(id: 1, child: secondRoom),
      ],
    );
  }
}

class _FoldTwoRoomDelegate extends MultiChildLayoutDelegate {
  _FoldTwoRoomDelegate(this.foldState);

  final FoldState foldState;
  static const double _outerMargin = ShioriSpace.s16;
  static const double _clearanceGutter =
      FoldLayoutSpec.creaseBandWidth + 2 * ShioriSpace.s16;

  @override
  void performLayout(Size size) {
    final isInnerPortrait = foldState == FoldState.innerPortrait;
    final isSplit =
        foldState == FoldState.innerPortrait ||
        foldState == FoldState.innerLandscape ||
        foldState == FoldState.halfOpen;
    if (isInnerPortrait) {
      final roomWidth = (size.width - 2 * _outerMargin - _clearanceGutter) / 2;
      final roomHeight = size.height - 2 * _outerMargin;
      layoutChild(0, BoxConstraints.tight(Size(roomWidth, roomHeight)));
      positionChild(0, const Offset(_outerMargin, _outerMargin));
      layoutChild(1, BoxConstraints.tight(Size(roomWidth, roomHeight)));
      positionChild(
        1,
        Offset(_outerMargin + roomWidth + _clearanceGutter, _outerMargin),
      );
      return;
    }

    if (isSplit) {
      final roomHeight =
          (size.height - 2 * _outerMargin - _clearanceGutter) / 2;
      final roomWidth = size.width - 2 * _outerMargin;
      layoutChild(0, BoxConstraints.tight(Size(roomWidth, roomHeight)));
      positionChild(0, const Offset(_outerMargin, _outerMargin));
      layoutChild(1, BoxConstraints.tight(Size(roomWidth, roomHeight)));
      positionChild(
        1,
        Offset(_outerMargin, _outerMargin + roomHeight + _clearanceGutter),
      );
      return;
    }

    final roomHeight = (size.height - 3 * _outerMargin) / 2;
    final roomWidth = size.width - 2 * _outerMargin;
    layoutChild(0, BoxConstraints.tight(Size(roomWidth, roomHeight)));
    positionChild(0, const Offset(_outerMargin, _outerMargin));
    layoutChild(1, BoxConstraints.tight(Size(roomWidth, roomHeight)));
    positionChild(1, Offset(_outerMargin, 2 * _outerMargin + roomHeight));
  }

  @override
  bool shouldRelayout(_FoldTwoRoomDelegate oldDelegate) =>
      foldState != oldDelegate.foldState;
}
