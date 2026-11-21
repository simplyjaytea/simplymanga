import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/l10n/l10n_delegates.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/modules/more/settings/browse/source_repositories.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/services/curated_repositories.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    List<Repo> installed = const [],
    ItemType itemType = ItemType.anime,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          extensionsRepoStateProvider(itemType)
              .overrideWith(() => _StubRepoState(installed)),
          // The counts come from the installed sources in Isar.
          repoSourceCountsProvider(itemType).overrideWith(
            (ref) => Stream.value(<String?, int>{
              for (final repo in installed) repo.jsonUrl: 1,
            }),
          ),
          for (final repository in curatedRepositoriesFor(itemType))
            getRepoInfosProvider(jsonUrl: repository.jsonUrl).overrideWith(
              (ref) async =>
                  Repo(name: repository.name, jsonUrl: repository.jsonUrl),
            ),
          l10nLocaleStateProvider.overrideWith(_StubLocale.new),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: Brightness.dark),
          home: SourceRepositories(itemType: itemType),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers the curated sources above the repositories', (
    tester,
  ) async {
    await pump(
      tester,
      installed: [
        Repo(
          name: 'Example',
          jsonUrl: 'https://example.invalid/anime_index.json',
        ),
      ],
    );

    expect(find.text('Curated sources'), findsOneWidget);
    expect(find.text('Example'), findsOneWidget);
  });

  testWidgets('the curated row opens the suggestions for this library', (
    tester,
  ) async {
    await pump(
      tester,
      installed: [
        Repo(
          name: 'Example',
          jsonUrl: 'https://example.invalid/anime_index.json',
        ),
      ],
    );

    await tester.tap(find.text('Curated sources'));
    await tester.pumpAndSettle();

    // The sheet's own content: the anime suggestions, and not manga's.
    expect(find.text('Mallyd11 anime'), findsOneWidget);
    expect(find.text('Aidoku community sources'), findsNothing);
  });

  testWidgets('once every suggestion is in, the row stops suggesting', (
    tester,
  ) async {
    await pump(
      tester,
      installed: [
        for (final repository in curatedRepositoriesFor(ItemType.anime))
          Repo(name: repository.name, jsonUrl: repository.jsonUrl),
      ],
    );

    expect(find.text('Curated sources'), findsOneWidget);
    expect(
      find.text('Recommended repositories, checked for this library'),
      findsNothing,
    );
    expect(find.text('Installed'), findsOneWidget);
  });

  testWidgets('an empty list leads with the suggestions too', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Curated sources'));
    await tester.pumpAndSettle();

    expect(find.text('m2k3a extensions'), findsOneWidget);
  });
}

/// A repository list held in memory instead of Isar.
class _StubRepoState extends ExtensionsRepoState {
  _StubRepoState(this._initial);

  final List<Repo> _initial;

  @override
  List<Repo> build(ItemType itemType) => _initial;

  @override
  Future<void> set(List<Repo> value) async {
    state = value;
  }
}

class _StubLocale extends L10nLocaleState {
  @override
  Locale build() => const Locale('en');

  @override
  void setLocale(Locale locale) => state = locale;

  @override
  void adoptDeviceLocaleIfUnset() {}
}
