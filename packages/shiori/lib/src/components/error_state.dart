import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../tokens.dart';
import 'button.dart';

/// A failure state with actionable recovery and optional diagnostic detail.
///
/// Text is supplied by the caller so apps can use their own localization
/// catalogs. Technical details are intentionally secondary and bounded.
class ShioriErrorState extends StatelessWidget {
  const ShioriErrorState({
    super.key,
    required this.title,
    this.detail,
    this.retryLabel,
    this.onRetry,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
    this.compact = false,
    this.autofocusRetry = false,
  });

  final String title;
  final String? detail;
  final String? retryLabel;
  final VoidCallback? onRetry;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;
  final bool compact;
  final bool autofocusRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.shiori;
    final c = tokens.color;
    final detailText = detail?.trim();
    final circle = tokens.scaled(compact ? 56 : 72);

    return Semantics(
      liveRegion: true,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: ShioriSpace.s24,
            vertical: compact ? ShioriSpace.s16 : ShioriSpace.s32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: circle,
                  height: circle,
                  decoration: BoxDecoration(
                    color: c.error.background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.error_rounded,
                    size: circle * 0.5,
                    color: c.error.foreground,
                  ),
                ),
              ),
              SizedBox(height: compact ? ShioriSpace.s12 : ShioriSpace.s16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: tokens.text.section.copyWith(color: c.fg),
              ),
              if (detailText != null && detailText.isNotEmpty) ...[
                const SizedBox(height: ShioriSpace.s8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Text(
                    detailText,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text.meta.copyWith(color: c.fgMuted),
                  ),
                ),
              ],
              if ((onRetry != null && retryLabel != null) ||
                  (onSecondary != null && secondaryLabel != null)) ...[
                SizedBox(height: compact ? ShioriSpace.s16 : ShioriSpace.s24),
                Wrap(
                  spacing: ShioriSpace.s8,
                  runSpacing: ShioriSpace.s8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (onRetry != null && retryLabel != null)
                      ShioriButton.secondary(
                        autofocus: autofocusRetry,
                        onPressed: onRetry,
                        icon: Symbols.refresh_rounded,
                        label: retryLabel!,
                      ),
                    if (onSecondary != null && secondaryLabel != null)
                      ShioriButton.quiet(
                        onPressed: onSecondary,
                        icon: secondaryIcon,
                        label: secondaryLabel!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A compact, non-terminal notice that playback is waiting for a user action.
///
/// Callers provide localized copy and an action that opens the challenged
/// source. It deliberately does not imply that the challenge was solved.
class ShioriChallengePendingBanner extends StatelessWidget {
  const ShioriChallengePendingBanner({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.shiori;
    final c = tokens.color;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(ShioriSpace.s16),
      decoration: BoxDecoration(
        color: c.ink2,
        borderRadius: BorderRadius.circular(ShioriShape.card),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.security_rounded, color: c.accent),
          const SizedBox(width: ShioriSpace.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.text.section.copyWith(color: c.fg),
                ),
                const SizedBox(height: ShioriSpace.s4),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.text.body.copyWith(color: c.fgMuted),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: ShioriSpace.s8),
                  ShioriButton.quiet(label: actionLabel!, onPressed: onAction),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
