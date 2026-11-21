import 'package:bot_toast/bot_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/l10n/generated/app_localizations.dart';
import 'package:mangayomi/l10n/l10n_delegates.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/models/settings.dart';
import 'package:mangayomi/modules/more/settings/browse/providers/browse_state_provider.dart';
import 'package:mangayomi/modules/more/settings/browse/widgets/curated_sources_sheet.dart';
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/services/curated_repositories.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shiori/shiori.dart';

const _m2k3aAnime =
    'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json';
const _mallyd11Anime =
    'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json';

void main() {
  setUp(_StubRepoState.reset);

  /// The success and failure toasts live for ten seconds on BotToast's own
  /// timers. Left running, they outlive the tree and fail the test that
  /// follows; letting them elapse is what a reader sees anyway.
  Future<void> letToastsExpire(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
  }

  Future<void> pump(
    WidgetTester tester, {
    ItemType itemType = ItemType.anime,
    List<Repo> installed = const [],
    Set<String> unresolved = const {},
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Writing goes through Isar, which is not open in a test.
          extensionsRepoStateProvider(itemType)
              .overrideWith(() => _StubRepoState(installed)),
          // Every suggestion resolves, so nothing needs the network; the last
          // test takes one away on purpose.
          for (final repository in curatedRepositoriesFor(itemType))
            getRepoInfosProvider(jsonUrl: repository.jsonUrl).overrideWith(
              (ref) async => unresolved.contains(repository.jsonUrl)
                  ? null
                  : Repo(name: repository.name, jsonUrl: repository.jsonUrl),
            ),
          // The screen reads the locale from Isar too.
          l10nLocaleStateProvider.overrideWith(_StubLocale.new),
        ],
        child: MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(brightness: Brightness.dark),
          // Toasts are part of what adding does; BotToast needs its overlay to
          // host them, and its timers are cleared in tearDown.
          builder: BotToastInit(),
          navigatorObservers: [BotToastNavigatorObserver()],
          home: Scaffold(
            body: SingleChildScrollView(
              child: CuratedSourcesSheet(itemType: itemType),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder rowFor(String name) => find.ancestor(
    of: find.text(name),
    matching: find.byType(ShioriSettingRow),
  );

  Finder addButtonFor(String name) => find.descendant(
    of: rowFor(name),
    matching: find.widgetWithText(ShioriButton, 'Add'),
  );

  testWidgets('lists only the suggestions for this library', (tester) async {
    await pump(tester);

    expect(find.text('m2k3a extensions'), findsOneWidget);
    expect(find.text('Mallyd11 anime'), findsOneWidget);
    expect(find.text('QuillDev extensions'), findsOneWidget);
    // Another library's suggestions are not this screen's business.
    expect(find.text('Aidoku community sources'), findsNothing);
    expect(find.text('LNReader plugins'), findsNothing);
    // The verified counts are said, so the choice is informed.
    expect(find.textContaining('64 sources'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsWidgets);
  });

  testWidgets('adding a suggestion goes through the add-repo path', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(addButtonFor('Mallyd11 anime'));
    await tester.pumpAndSettle();

    expect(_StubRepoState.saved.keys, [ItemType.anime]);
    expect(_StubRepoState.saved[ItemType.anime]!.map((r) => r.jsonUrl), [
      _mallyd11Anime,
    ]);
    // The row now reads as installed, and its button is gone.
    expect(find.text('Installed'), findsOneWidget);
    expect(addButtonFor('Mallyd11 anime'), findsNothing);
    expect(find.widgetWithText(ShioriButton, 'Add'), findsNWidgets(2));

    await letToastsExpire(tester);
  });

  testWidgets('a repository already installed is not offered again', (
    tester,
  ) async {
    await pump(
      tester,
      installed: [Repo(name: 'm2k3a extensions', jsonUrl: _m2k3aAnime)],
    );

    expect(find.text('Installed'), findsOneWidget);
    expect(addButtonFor('m2k3a extensions'), findsNothing);
    expect(find.widgetWithText(ShioriButton, 'Add'), findsNWidgets(2));
    expect(_StubRepoState.saved, isEmpty);
  });

  testWidgets('tap and button do the same thing, once', (tester) async {
    await pump(tester);

    await tester.tap(find.text('QuillDev extensions'));
    await tester.pumpAndSettle();

    expect(_StubRepoState.saved[ItemType.anime], hasLength(1));
    expect(
      _StubRepoState.saved[ItemType.anime]!.single.jsonUrl,
      contains('QuillDev'),
    );

    await letToastsExpire(tester);
  });

  testWidgets('a suggestion that does not resolve adds nothing', (
    tester,
  ) async {
    await pump(tester, unresolved: {_m2k3aAnime});

    await tester.tap(addButtonFor('m2k3a extensions'));
    await tester.pumpAndSettle();

    expect(_StubRepoState.saved, isEmpty);
    expect(addButtonFor('m2k3a extensions'), findsOneWidget);

    await letToastsExpire(tester);
  });
}

/// A repository list held in memory instead of Isar.
class _StubRepoState extends ExtensionsRepoState {
  _StubRepoState(this._initial);

  final List<Repo> _initial;

  /// What each library's list was last set to.
  static final saved = <ItemType, List<Repo>>{};

  static void reset() {
    saved.clear();
  }

  @override
  List<Repo> build(ItemType itemType) => _initial;

  @override
  Future<void> set(List<Repo> value) async {
    saved[itemType] = value;
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
