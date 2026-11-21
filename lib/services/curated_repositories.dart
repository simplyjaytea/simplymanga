import 'package:mangayomi/models/manga.dart';

/// A repository the app offers as a suggestion rather than waiting for the
/// reader to find one.
///
/// The app ships no sources and no bundled repository list: sources are
/// downloaded from an index the reader trusts. That leaves a new install with
/// an empty Browse and no address to type, which is the worst place to start.
/// This is the short list the app can name, verified by hand and per library.
///
/// Only the *address* lives here. Extension code stays in its repository:
/// vendoring it would put site scrapers, and their licences, in the app
/// bundle, and they change far faster than the app does.
///
/// The addresses below were fetched live on 2026-11-21 (see
/// `analysis/08-source-repos.md`). This is the one place in `lib/` that knows
/// them, so re-verifying the list before a release means checking this file.
class CuratedRepository {
  const CuratedRepository({
    required this.name,
    required this.jsonUrl,
    required this.itemType,
    required this.sourceCount,
    required this.licence,
    required this.note,
  });

  /// What the repository calls itself, short enough for a list row.
  final String name;

  /// The index the app fetches and parses. The only thing that gets shipped.
  final String jsonUrl;

  /// The library this repository stocks. It is what the app will type its
  /// entries as: a MangaYomi index says so per entry (`itemType:1` for anime),
  /// while Aidoku and LNReader indexes are typed by the app itself, manga and
  /// novel respectively.
  final ItemType itemType;

  /// Sources in the index when it was last verified. Shown so the choice is
  /// informed, and a drift check when the list is re-verified.
  final int sourceCount;

  /// The repository's licence, from its own metadata. All are permissive
  /// enough to *point at* from an Apache-2.0 app.
  final String licence;

  /// One line on why it is worth adding, in English like the repository names
  /// it describes; these are names and counts, not translatable prose.
  final String note;

  @override
  String toString() => 'CuratedRepository($name, $jsonUrl)';
}

/// The suggested repositories, anime first: it is the library the app is built
/// around, and the one the ecosystem serves worst (the official MangaYomi repo
/// is archived and has never carried an anime source).
///
/// Deliberately excluded, with the dossier's reasons: the official
/// `kodjodevf` repository (archived, zero anime), `keiyoushi` (Mihon APKs,
/// which need an Android proxy this iOS-first app does not have), the aniyomi
/// archives (dead since 2024), the unlicensed anime forks, and the mirrors of
/// the repositories below (add the origin, not a copy of it).
const curatedRepositories = <CuratedRepository>[
  // Anime. Every one is MangaYomi format with `itemType: 1`, so its entries
  // run in the Dart or JavaScript interpreter already on the device.
  CuratedRepository(
    name: 'm2k3a extensions',
    jsonUrl: 'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
    itemType: ItemType.anime,
    sourceCount: 64,
    licence: 'Apache-2.0',
    note: 'Largest anime index — 19 languages',
  ),
  CuratedRepository(
    name: 'Mallyd11 anime',
    jsonUrl: 'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json',
    itemType: ItemType.anime,
    sourceCount: 17,
    licence: 'Apache-2.0',
    note: 'English anime, refreshed with fixes',
  ),
  CuratedRepository(
    name: 'QuillDev extensions',
    jsonUrl: 'https://raw.githubusercontent.com/QuillDev/mangayomi-extensions/main/anime_index.json',
    itemType: ItemType.anime,
    sourceCount: 24,
    licence: 'Apache-2.0',
    note: 'Anime only, chosen without NSFW',
  ),
  // Manga. The MangaYomi index for breadth; Aidoku's community index for
  // depth in languages it covers thinly. The app types Aidoku's `.aix`
  // entries manga whatever the index says.
  CuratedRepository(
    name: 'm2k3a extensions',
    jsonUrl: 'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/index.json',
    itemType: ItemType.manga,
    sourceCount: 335,
    licence: 'Apache-2.0',
    note: 'Largest manga index',
  ),
  CuratedRepository(
    name: 'Aidoku community sources',
    jsonUrl: 'https://raw.githubusercontent.com/Aidoku-Community/sources/gh-pages/index.min.json',
    itemType: ItemType.manga,
    sourceCount: 180,
    licence: 'Apache-2.0 / MIT',
    note: 'WASM sources, deep in ja, zh, vi and more',
  ),
  // Novels. LNReader's plugins are typed novel by the app; the MangaYomi
  // novel index is small but native.
  CuratedRepository(
    name: 'LNReader plugins',
    jsonUrl: 'https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json',
    itemType: ItemType.novel,
    sourceCount: 373,
    licence: 'MIT',
    note: 'Largest novel index',
  ),
  CuratedRepository(
    name: 'm2k3a extensions',
    jsonUrl: 'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/novel_index.json',
    itemType: ItemType.novel,
    sourceCount: 9,
    licence: 'Apache-2.0',
    note: 'A few native novel sources',
  ),
];

/// The suggestions for one library, in the order they should be shown.
List<CuratedRepository> curatedRepositoriesFor(ItemType itemType) =>
    curatedRepositories
        .where((repository) => repository.itemType == itemType)
        .toList(growable: false);

/// How the app tells two spellings of one repository apart, or fails to:
/// trimmed, lower case, no trailing slash. It matches the check the add-repo
/// dialog and the settings list already use, so a repository added by hand is
/// recognised as the suggestion it is.
String curatedRepositoryKey(String? jsonUrl) {
  final url = (jsonUrl ?? '').trim().toLowerCase();
  return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
}

/// Whether [repository] is among the addresses already installed.
bool isCuratedRepositoryInstalled(
  CuratedRepository repository,
  Iterable<String?> installedJsonUrls,
) {
  final key = curatedRepositoryKey(repository.jsonUrl);
  return installedJsonUrls.any(
    (url) => key.isNotEmpty && curatedRepositoryKey(url) == key,
  );
}

/// The suggestions for [itemType] that are not already installed, so the app
/// offers what is missing instead of a list the reader has to check by hand.
List<CuratedRepository> missingCuratedRepositories(
  ItemType itemType,
  Iterable<String?> installedJsonUrls,
) {
  final installed = installedJsonUrls
      .map(curatedRepositoryKey)
      .where((key) => key.isNotEmpty)
      .toSet();
  return curatedRepositoriesFor(itemType)
      .where(
        (repository) =>
            !installed.contains(curatedRepositoryKey(repository.jsonUrl)),
      )
      .toList(growable: false);
}
