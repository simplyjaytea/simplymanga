import 'package:flutter_test/flutter_test.dart';
import 'package:mangayomi/models/manga.dart';
import 'package:mangayomi/services/curated_repositories.dart';

/// The index URLs verified live on 2026-11-21 in
/// `analysis/08-source-repos.md`. The curated list ships *these* addresses and
/// nothing else: a URL the dossier did not verify has no business being
/// suggested to a reader.
const _verified = {
  // Anime — MangaYomi format, itemType 1.
  'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json':
      64,
  'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json':
      17,
  'https://raw.githubusercontent.com/QuillDev/mangayomi-extensions/main/anime_index.json':
      24,
  // Manga — MangaYomi format itemType 0, and Aidoku's .aix index (typed manga
  // by the app, ESS:320).
  'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/index.json':
      335,
  'https://raw.githubusercontent.com/Aidoku-Community/sources/gh-pages/index.min.json':
      180,
  // Novels — LNReader plugins are typed novel by the app (ESS:516).
  'https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json':
      373,
  'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/novel_index.json':
      9,
};

/// Repositories the dossier rules out, by host or owner, and the mirrors it
/// says to leave alone. None may appear in the curated list.
const _excluded = [
  'kodjodevf', // archived, zero anime
  'keiyoushi', // Mihon APKs, Android bridge only
  'aniyomiorg', // archived 2024
  'jmir1', // the aniyomi archive under another name
  'shuwenLiao', // unlicensed, NSFW-heavy
  'adam72881', // unlicensed
  'mrandhawa14', // stale, NSFW-heavy
  'fabianoridolfi', // mirror of m2k3a
  '5y3b', // mirror of m2k3a
  'manubte', // mirror of m2k3a
  'NBA2K1', // mirror of m2k3a
  'kingsiruss', // mirror of m2k3a
  'kfongh', // stale mirror of Mallyd11
  'lvstresss', // stale mirror of Mallyd11
];

void main() {
  group('curated repositories', () {
    test('ship exactly the dossier-verified index URLs', () {
      expect(
        curatedRepositories.map((r) => r.jsonUrl).toSet(),
        _verified.keys.toSet(),
      );
    });

    test('source counts match the verified indexes', () {
      for (final repository in curatedRepositories) {
        expect(
          repository.sourceCount,
          _verified[repository.jsonUrl],
          reason: repository.jsonUrl,
        );
      }
    });

    test('every entry is https, a .json index, and unique', () {
      final urls = curatedRepositories.map((r) => r.jsonUrl).toList();
      expect(urls.toSet(), hasLength(urls.length));
      for (final url in urls) {
        final uri = Uri.parse(url);
        expect(uri.scheme, 'https', reason: url);
        expect(uri.path, endsWith('.json'), reason: url);
      }
    });

    test('no excluded or unverified repository is suggested', () {
      for (final repository in curatedRepositories) {
        final url = repository.jsonUrl.toLowerCase();
        for (final banned in _excluded) {
          expect(
            url,
            isNot(contains(banned.toLowerCase())),
            reason: '${repository.name} points at $banned',
          );
        }
      }
    });

    test('every entry names its licence and says what it brings', () {
      for (final repository in curatedRepositories) {
        expect(repository.name.trim(), isNotEmpty);
        expect(repository.licence.trim(), isNotEmpty);
        expect(repository.note.trim(), isNotEmpty);
        expect(repository.sourceCount, greaterThan(0));
      }
    });
  });

  group('grouping by itemType', () {
    test('anime is MangaYomi format only, with itemType 1', () {
      final anime = curatedRepositoriesFor(ItemType.anime);
      expect(anime, hasLength(3));
      for (final repository in anime) {
        expect(repository.itemType, ItemType.anime);
        expect(repository.jsonUrl, endsWith('anime_index.json'));
      }
      expect(
        anime.map((r) => r.jsonUrl),
        containsAll([
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json',
          'https://raw.githubusercontent.com/Mallyd11/mangayomi-anime-extensions/main/anime_index.json',
          'https://raw.githubusercontent.com/QuillDev/mangayomi-extensions/main/anime_index.json',
        ]),
      );
    });

    test('manga is the MangaYomi index plus Aidoku community', () {
      final manga = curatedRepositoriesFor(ItemType.manga);
      expect(manga, hasLength(2));
      for (final repository in manga) {
        expect(repository.itemType, ItemType.manga);
      }
      expect(
        manga.map((r) => r.jsonUrl),
        containsAll([
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/index.json',
          'https://raw.githubusercontent.com/Aidoku-Community/sources/gh-pages/index.min.json',
        ]),
      );
    });

    test('novel is LNReader plus the small MangaYomi index', () {
      final novel = curatedRepositoriesFor(ItemType.novel);
      expect(novel, hasLength(2));
      for (final repository in novel) {
        expect(repository.itemType, ItemType.novel);
      }
      expect(
        novel.map((r) => r.jsonUrl),
        containsAll([
          'https://raw.githubusercontent.com/LNReader/lnreader-plugins/plugins/v3.0.0/.dist/plugins.min.json',
          'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/novel_index.json',
        ]),
      );
    });

    test('each group is exactly the entries carrying its itemType', () {
      for (final type in ItemType.values) {
        expect(
          curatedRepositoriesFor(type).map((r) => r.jsonUrl).toSet(),
          curatedRepositories
              .where((r) => r.itemType == type)
              .map((r) => r.jsonUrl)
              .toSet(),
          reason: type.name,
        );
      }
    });

    test('no ItemType is left without a suggestion', () {
      for (final type in ItemType.values) {
        expect(curatedRepositoriesFor(type), isNotEmpty, reason: type.name);
      }
    });
  });

  group('already installed', () {
    const m2k3aAnime =
        'https://raw.githubusercontent.com/m2k3a/mangayomi-extensions/main/anime_index.json';

    test('a repository already in the list is not offered again', () {
      final missing = missingCuratedRepositories(ItemType.anime, [m2k3aAnime]);
      expect(missing.map((r) => r.jsonUrl), isNot(contains(m2k3aAnime)));
      expect(missing, hasLength(2));
    });

    test('a trailing slash or different case still counts as installed', () {
      final missing = missingCuratedRepositories(ItemType.anime, [
        '  ${m2k3aAnime.toUpperCase()}/  ',
      ]);
      expect(missing.map((r) => r.jsonUrl), isNot(contains(m2k3aAnime)));
    });

    test('null and empty installed addresses are ignored, not matched', () {
      final missing = missingCuratedRepositories(ItemType.anime, [
        null,
        '',
        '   ',
      ]);
      expect(missing, hasLength(3));
    });

    test('an entry is installed when any listed address is its own', () {
      final m2k3a = curatedRepositoriesFor(ItemType.anime).first;
      expect(
        isCuratedRepositoryInstalled(m2k3a, ['https://example.invalid/x.json']),
        isFalse,
      );
      expect(isCuratedRepositoryInstalled(m2k3a, [m2k3aAnime]), isTrue);
    });

    test('the remaining count drops as repositories are added', () {
      expect(
        missingCuratedRepositories(ItemType.anime, const []),
        hasLength(3),
      );
      expect(
        missingCuratedRepositories(ItemType.anime, [
          for (final repository in curatedRepositoriesFor(ItemType.anime))
            repository.jsonUrl,
        ]),
        isEmpty,
      );
    });

    test('one library\'s installs say nothing about another\'s', () {
      final animeUrls = curatedRepositoriesFor(ItemType.anime)
          .map((r) => r.jsonUrl)
          .toList();
      expect(
        missingCuratedRepositories(ItemType.manga, animeUrls),
        hasLength(2),
      );
    });
  });
}
