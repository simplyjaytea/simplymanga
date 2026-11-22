import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shiori/shiori.dart';

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
  Timer? _settleTimer;
  FoldState _currentState;
  bool _disposed = false;

  @override
  FoldState get currentState => _currentState;

  @override
  Stream<FoldState> get states => _states.stream;

  void report(FoldState state) {
    if (_disposed) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(debounce, () => _settle(state));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _settleTimer?.cancel();
    unawaited(_states.close());
  }

  void _settle(FoldState state) {
    if (_disposed || state == _currentState) return;
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
class FoldAwareShell extends StatefulWidget {
  const FoldAwareShell({super.key, required this.driver, required this.child});

  final FoldStateDriver driver;
  final Widget child;

  @override
  State<FoldAwareShell> createState() => _FoldAwareShellState();
}

class _FoldAwareShellState extends State<FoldAwareShell> {
  late FoldState _foldState = widget.driver.currentState;
  StreamSubscription<FoldState>? _subscription;

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
      _foldState = widget.driver.currentState;
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.driver.states.listen((state) {
      if (mounted) setState(() => _foldState = state);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final spec = FoldLayoutSpec.resolve(
          foldState: _foldState,
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
        return FoldLayoutScope(
          spec: spec,
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
  const FoldLayoutScope({super.key, required this.spec, required super.child});

  final FoldLayoutSpec spec;

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
      spec.usesTwoPaneDetail != oldWidget.spec.usesTwoPaneDetail;
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
