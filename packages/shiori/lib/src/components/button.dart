import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../alphas.dart';
import '../tokens.dart';

/// The three levels of action. A screen has at most one [primary].
enum ShioriButtonVariant {
  /// The action the screen exists for: "Resume", "Add to library".
  primary,

  /// An alternative to the primary: "Track", "Filter".
  secondary,

  /// A low-key action: "Cancel", "Show all".
  quiet,
}

/// A button at one of Shiori's three levels.
///
/// Built on Material's buttons, so focus, hover, keyboard activation and
/// semantics come for free; Shiori only decides how each level looks, and
/// how each state is met: a touch presses the whole button for as long as
/// it lasts, and a running action replaces the glyph with a spinner while
/// the label keeps its name.
class ShioriButton extends StatefulWidget {
  const ShioriButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ShioriButtonVariant.primary,
    this.icon,
    this.destructive = false,
    this.expand = false,
    this.autofocus = false,
    this.loading = false,
  });

  const ShioriButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.expand = false,
    this.autofocus = false,
    this.loading = false,
  }) : variant = ShioriButtonVariant.secondary;

  const ShioriButton.quiet({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.expand = false,
    this.autofocus = false,
    this.loading = false,
  }) : variant = ShioriButtonVariant.quiet;

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final ShioriButtonVariant variant;

  /// An optional leading `Symbols.*_rounded` glyph.
  final IconData? icon;

  /// For actions that delete or discard: drawn in the error colours.
  final bool destructive;

  /// Fills the available width.
  final bool expand;
  final bool autofocus;

  /// True while the action runs. The glyph becomes a spinner, the label
  /// stays so the button keeps its name, and taps do nothing.
  final bool loading;

  @override
  State<ShioriButton> createState() => _ShioriButtonState();
}

class _ShioriButtonState extends State<ShioriButton> {
  /// Whether a pointer is down on the button. A [Listener], not a gesture
  /// recognizer: it watches the pointer without ever competing with the
  /// Material button's own recognition.
  bool _pressed = false;

  /// Whether the button can be used right now: an action to run, and not
  /// busy. Nothing presses a button that cannot be used.
  bool get _usable => widget.onPressed != null && !widget.loading;

  void _setPressed(bool value) {
    final pressed = value && _usable;
    if (_pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.shiori;
    final scheme = Theme.of(context).colorScheme;
    final c = tokens.color;
    final loading = widget.loading;

    // The floor every interactive target clears for a thumb, whatever the
    // pointing device: the density's own floor, or iOS's 44 pt, whichever
    // is larger.
    final target = math.max(tokens.density.minTarget, 44.0);

    final (Color bg, Color fg) = switch (widget.variant) {
      ShioriButtonVariant.primary =>
        widget.destructive
            ? (scheme.error, scheme.onError)
            : (c.accent, c.onAccent),
      ShioriButtonVariant.secondary => (
        c.ink2,
        widget.destructive ? c.error.foreground : c.fg,
      ),
      ShioriButtonVariant.quiet => (
        Colors.transparent,
        widget.destructive ? c.error.foreground : c.accentInk,
      ),
    };

    // Busy is unavailable: the callback is dropped so semantics and taps
    // agree that nothing can be asked of it yet.
    final onPressed = loading ? null : widget.onPressed;
    final enabled = onPressed != null;

    final style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? (widget.variant == ShioriButtonVariant.quiet
                  ? Colors.transparent
                  : c.fg.withValues(alpha: Alphas.tint))
            : bg,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? c.fg.withValues(alpha: Alphas.disabled)
            : fg,
      ),
      overlayColor: WidgetStatePropertyAll(fg.withValues(alpha: Alphas.focus)),
      minimumSize: WidgetStatePropertyAll(Size(target, target)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: ShioriSpace.s16),
      ),
      shape: const WidgetStatePropertyAll(StadiumBorder()),
      textStyle: WidgetStatePropertyAll(
        tokens.text.row.copyWith(fontWeight: FontWeight.w700),
      ),
      elevation: const WidgetStatePropertyAll(0),
      animationDuration: ShioriMotion.fast,
    );

    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final child = loading
        ? Row(
            mainAxisSize: MainAxisSize.min,
            spacing: ShioriSpace.s8,
            children: [
              ExcludeSemantics(
                child: SizedBox.square(
                  dimension: tokens.scaled(18),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    strokeCap: StrokeCap.round,
                    color: fg,
                  ),
                ),
              ),
              Flexible(child: label),
            ],
          )
        : widget.icon == null
        ? label
        : Row(
            mainAxisSize: MainAxisSize.min,
            spacing: ShioriSpace.s8,
            children: [
              Icon(widget.icon, size: tokens.scaled(20)),
              Flexible(child: label),
            ],
          );

    final button = AnimatedScale(
      // Weight, not travel: a short step towards the reader for exactly
      // as long as the touch lasts.
      scale: _pressed && enabled ? ShioriMotion.pressedScale : 1,
      duration: ShioriMotion.of(context, ShioriMotion.fast),
      curve: ShioriMotion.standardCurve,
      child: widget.variant == ShioriButtonVariant.quiet
          ? TextButton(
              onPressed: onPressed,
              autofocus: widget.autofocus,
              style: style,
              child: child,
            )
          : FilledButton(
              onPressed: onPressed,
              autofocus: widget.autofocus,
              style: style,
              child: child,
            ),
    );
    final pressed = Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: button,
    );
    return widget.expand
        ? SizedBox(width: double.infinity, child: pressed)
        : pressed;
  }
}
