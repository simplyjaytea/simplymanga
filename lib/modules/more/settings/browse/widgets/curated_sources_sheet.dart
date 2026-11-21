import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mangayomi/eval/model/m_bridge.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/services/curated_repositories.dart';
import 'package:mangayomi/utils/error_toast.dart';
import 'package:shiori/shiori.dart';

/// The repositories the app recommends for one library, with an Add button on
/// each that has not been added yet.
///
/// It installs nothing itself: adding a suggestion goes through the same
/// `getRepoInfosProvider` fetch and repository list as typing the address into
/// the add-repo dialog, so a suggestion is only ever a filled-in URL field.
///
/// Shown in a sheet from the repository screen (Settings → Browse → Manga /
/// Anime / Novel repositories).
class CuratedSourcesSheet extends ConsumerStatefulWidget {
  const CuratedSourcesSheet({required this.itemType, super.key});

  final ItemType itemType;

  @override
  ConsumerState<CuratedSourcesSheet> createState() =>
      _CuratedSourcesSheetState();
}

class _CuratedSourcesSheetState extends ConsumerState<CuratedSourcesSheet> {
  /// The suggestions being added right now, by index URL, so each row spins on
  /// its own button and the rest stay usable.
  final _installing = <String>{};

  Future<void> _install(CuratedRepository suggestion) async {
    if (_installing.contains(suggestion.jsonUrl)) return;
    final l10n = context.l10n;
    setState(() => _installing.add(suggestion.jsonUrl));
    try {
      final repo = await ref.read(
        getRepoInfosProvider(jsonUrl: suggestion.jsonUrl).future,
      );
      if (!mounted) return;
      if (repo == null) {
        botToast(l10n.unsupported_repo);
        return;
      }
      final current = ref.read(extensionsRepoStateProvider(widget.itemType));
      if (isCuratedRepositoryInstalled(
        suggestion,
        current.map((r) => r.jsonUrl),
      )) {
        botToast(l10n.repo_already_exists);
        return;
      }
      await ref.read(extensionsRepoStateProvider(widget.itemType).notifier).set(
        [...current, repo],
      );
      botToast(l10n.repo_added);
    } catch (e, s) {
      toastError(e, stack: s, source: 'curatedSources');
    } finally {
      if (mounted) setState(() => _installing.remove(suggestion.jsonUrl));
    }
  }

  IconData get _icon => switch (widget.itemType) {
    ItemType.manga => Symbols.menu_book_rounded,
    ItemType.anime => Symbols.live_tv_rounded,
    ItemType.novel => Symbols.auto_stories_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final installed = ref.watch(extensionsRepoStateProvider(widget.itemType));
    final installedUrls = installed.map((repo) => repo.jsonUrl).toList();
    return ShioriSettingsGroup(
      // The one thing the rows cannot say for themselves: these are addresses,
      // and what they point at runs inside the app.
      footer: l10n.add_repo_warning,
      children: [
        for (final suggestion in curatedRepositoriesFor(widget.itemType))
          _row(suggestion, installedUrls, l10n),
      ],
    );
  }

  Widget _row(
    CuratedRepository suggestion,
    List<String?> installedUrls,
    AppLocalizations l10n,
  ) {
    final isInstalled = isCuratedRepositoryInstalled(suggestion, installedUrls);
    return ShioriSettingRow(
      icon: _icon,
      title: suggestion.name,
      // What it brings, then what it costs to trust: its licence.
      subtitle:
          '${suggestion.note} · '
          '${l10n.n_sources(suggestion.sourceCount)} · '
          '${suggestion.licence}',
      trailing: isInstalled
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.check_rounded,
                  size: 18,
                  color: context.shiori.color.fgMuted,
                ),
                const SizedBox(width: ShioriSpace.s4),
                Text(
                  l10n.installed,
                  style: context.shiori.text.meta.copyWith(
                    color: context.shiori.color.fgMuted,
                  ),
                ),
              ],
            )
          : ShioriButton.quiet(
              label: l10n.add,
              loading: _installing.contains(suggestion.jsonUrl),
              onPressed: () => _install(suggestion),
            ),
      // The whole row adds it too, as a settings row does; an installed one
      // has nothing left to do.
      onTap: isInstalled ? null : () => _install(suggestion),
    );
  }
}
