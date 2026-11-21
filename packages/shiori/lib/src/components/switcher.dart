import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// How one piece of content replaces another in the same place.
enum ShioriSwitchMode {
  /// Cross-fades. The default, and what every movement degrades to under
  /// "Reduce Motion".
  fade,

  /// Up from just below where it will sit, fading in as it rises.
  rise,

  /// In from the leading edge, fading in as it travels.
  slideStart,

  /// In from the trailing edge, fading in as it travels.
  slideEnd,
}

/// One piece of content replacing another in the same place: a value that
/// finishes loading, a list that turns out to be empty, a label that
/// changes its mind.
///
/// Give the changing children different keys (or different types), and
/// this crosses them over on the motion tokens: [ShioriMotion.medium] on
/// the way in, [ShioriMotion.decelerateCurve] arriving and
/// [ShioriMotion.accelerateCurve] leaving. A reader who asked for less
/// movement gets the fade without the travel; a reader who asked for none
/// gets the new content simply there.
///
/// For whole screens of kept-alive content — tabs, a pane's pages —
/// prefer [ShioriFadeThroughStack], which never unmounts what it hides.
class ShioriSwitcher extends StatelessWidget {
  const ShioriSwitcher({
    super.key,
    required this.child,
    this.mode = ShioriSwitchMode.fade,
    this.duration,
  });

  /// The content shown now. Changing its key (or its type) is the switch.
  final Widget child;

  final ShioriSwitchMode mode;

  /// The switch's length. Defaults to [ShioriMotion.medium].
  final Duration? duration;

  /// How far a rising child begins below where it will sit, as a share of
  /// its own height: enough to be seen arriving, not enough to look
  /// poured in from off screen.
  static const double _rise = 0.125;

  /// How far a sliding child begins from its edge, as a share of its own
  /// width.
  static const double _slide = 0.25;

  @override
  Widget build(BuildContext context) {
    // A reader who asked for no animation at all gets the new content
    // simply there; one who asked for less movement still gets the fade.
    final length = ShioriMotion.stillOf(context)
        ? Duration.zero
        : (duration ?? ShioriMotion.medium);
    final moving =
        mode != ShioriSwitchMode.fade && !ShioriMotion.reducedOf(context);
    // Leading and trailing, not left and right: the edges flip with the
    // writing direction.
    final rtl = Directionality.of(context) == TextDirection.rtl;

    return AnimatedSwitcher(
      duration: length,
      // Arrivals are seen from their first frames; departures are gone
      // before they are missed.
      switchInCurve: ShioriMotion.decelerateCurve,
      switchOutCurve: ShioriMotion.accelerateCurve,
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (!moving) return fade;
        final sign = rtl ? -1.0 : 1.0;
        final from = switch (mode) {
          ShioriSwitchMode.rise => const Offset(0, _rise),
          ShioriSwitchMode.slideStart => Offset(sign * -_slide, 0),
          ShioriSwitchMode.slideEnd => Offset(sign * _slide, 0),
          ShioriSwitchMode.fade => Offset.zero,
        };
        return SlideTransition(
          position: animation.drive(Tween(begin: from, end: Offset.zero)),
          child: fade,
        );
      },
      child: child,
    );
  }
}
