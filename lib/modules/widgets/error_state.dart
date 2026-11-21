import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/utils/platform_utils.dart';
import 'package:shiori/shiori.dart';

/// The shared failure state.
///
/// Screens used to render a bare `Center(child: Text(error.toString()))`, which
/// shows the user a stack trace, gives them nothing to do about it and looks
/// different in every place it appears. Use this instead: a readable line, the
/// technical cause kept but demoted, and a retry when the caller can offer one.
///
/// Every colour here comes from the theme, because the palette is chosen at
/// runtime and any fixed colour would be wrong on somebody else's scheme.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.message,
    this.detail,
    this.onRetry,
    this.compact = false,
    this.autofocusRetry,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
  });

  /// Human readable line. Falls back to a generic message when null.
  final String? message;

  /// Technical cause, kept for bug reports but visually demoted. Nothing is
  /// rendered for it when null or empty.
  final String? detail;

  /// Omitted when the caller has nothing useful to re-run.
  final VoidCallback? onRetry;

  /// Tightens the padding for use inside a list or a sheet rather than as a
  /// whole page.
  final bool compact;

  /// Whether the retry button claims focus on a TV. Defaults to taking it,
  /// since it is usually the only control on the screen. Pass false where the
  /// route already autofocuses something else, because two widgets competing
  /// for autofocus in one scope resolve arbitrarily.
  final bool? autofocusRetry;

  /// A second way out beside the retry, such as opening a source in the
  /// browser to get past Cloudflare. Shown with [onSecondary].
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ShioriErrorState(
      title: message ?? l10n.something_went_wrong,
      detail: detail,
      retryLabel: onRetry == null ? null : l10n.retry,
      onRetry: onRetry,
      secondaryLabel: secondaryLabel,
      secondaryIcon: secondaryIcon,
      onSecondary: onSecondary,
      compact: compact,
      autofocusRetry: autofocusRetry ?? isTv,
    );
  }
}
