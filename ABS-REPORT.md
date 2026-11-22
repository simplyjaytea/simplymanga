# Audiobookshelf slice — report

Branch: `lane/abs` (worktree `/root/projects/gilfoyle/simplyMANGA/wt-abs`), based on `a539958`.

## What was built

A minimal vertical slice for a self-hosted Audiobookshelf server:

- Connection screen: server URL + API token, **Test connection** (ping, then `/api/me`), save, disconnect.
- Library browse: the server's libraries (book libraries openable; podcast libraries listed dimmed), then a title-sorted, paged list of books with cover-or-placeholder, author and length.
- Player: media_kit audio playback, resume at the server's book position, play/pause, seek bar, previous/next file, automatic advance, best-effort progress save on pause, completion and dispose.
- Entry point: `Audiobookshelf` tile in More → `/audiobookshelf`.

## Files

Added:

- `lib/services/audiobookshelf/audiobookshelf_client.dart`
- `lib/services/audiobookshelf/audiobookshelf_models.dart`
- `lib/services/audiobookshelf/audiobookshelf_settings.dart`
- `lib/modules/audiobookshelf/abs_playback_math.dart`
- `lib/modules/audiobookshelf/audiobookshelf_connection_screen.dart`
- `lib/modules/audiobookshelf/audiobookshelf_home_screen.dart`
- `lib/modules/audiobookshelf/audiobookshelf_library_screen.dart`
- `lib/modules/audiobookshelf/audiobookshelf_player_screen.dart`
- `lib/modules/audiobookshelf/audiobookshelf_shared.dart`
- `test/services/audiobookshelf/audiobookshelf_client_test.dart`
- `test/services/audiobookshelf/audiobookshelf_settings_test.dart`
- `test/modules/audiobookshelf/abs_playback_math_test.dart`
- `test/modules/audiobookshelf/audiobookshelf_connection_screen_test.dart`

Changed:

- `lib/modules/more/more_screen.dart` — one `ListTileWidget` in the Library group.
- `lib/router/router.dart` — `/audiobookshelf`, `/audiobookshelfSetup`, `/audiobookshelfPlayer` registered through `_genericRoute`, like the existing routes.

No `pubspec.yaml`, arb, CI, manga/anime/novel/reader changes. No new dependencies.

## API surface used

`GET /api/ping`, `GET /api/me`, `GET /api/libraries`,
`GET /api/libraries/{id}/items` (`limit`, `page`, `sort=media.metadata.title`, `minified=1`),
`GET /api/items/{id}`, `POST /api/items/{id}/play`,
`PATCH /api/me/progress/{itemId}`, `GET /api/items/{id}/cover`.

## Client design

- Pure Dart (`http` + `dart:convert`/`dart:developer` only); `http.Client` injected, so every test is offline.
- `normalizeBaseUrl`: trims, adds `http://` when the user omits a scheme, strips trailing slashes, drops a pasted query/fragment, keeps a path prefix (`http://host/abs` → items under `/abs/api/...`).
- `streamUri`: resolves relative `contentUrl` under the base path and appends `?token=` (merging any existing query), because media_kit cannot send an Authorization header. Absolute `contentUrl`s are kept.
- Sealed `AbsException` hierarchy: `AbsUnreachableException`, `AbsUnauthorizedException` (401/403), `AbsServerErrorException` (5xx/other non-2xx/unparseable body), `AbsNotFoundException` (404); each carries a readable sentence.
- `saveProgress` swallows and debug-logs failures by design.
- Stable `deviceId` derived from base URL + token with FNV-1a (`simplymanga-<8 hex>`), so the server sees one device across launches without another stored secret.

## Settings design

- Tokens live in `flutter_secure_storage` under `abs_base_url` / `abs_token`.
- `AbsCredentialsStore` abstracts persistence; the real implementation wraps the app's existing `secureStorage`, tests use an in-memory store.
- `absSettingsProvider` (manual `AsyncNotifierProvider`) exposes the saved pair; `absClientProvider` builds the configured client and closes it on rebuild; `absClientFactoryProvider` is the seam widget tests override.

## Playback design

- Book-level position ↔ per-file position mapping is isolated in `abs_playback_math.dart` and unit-tested: resume at `session.currentTime` opens the right file at the right offset; progress reports use the absolute book position.
- media_kit `Player` (audio only), one file open at a time. Session `audioTracks` are preferred; item tracks are the fallback when the session has none (or has empty URLs). Generic `Track N` session names are replaced with the item's chapter titles.
- Progress is saved on pause, on finishing the last file (`isFinished: true`) and on dispose; failures never surface.

## Tests and results

TDD: the client/settings/playback tests were written first and failed to compile (`No such file or directory` for the client, playback math and settings modules) before implementation. The 23 client tests then passed on the first implementation run; settings and playback tests passed after the modules landed. The connection-screen widget tests initially failed because `enterText` needs a frame before the enabled button receives a tap; the tests now pump after typing.

Commands run (real output, this worktree, Flutter 3.50.1 / Dart 3.14.0):

```
flutter analyze
→ No issues found! (ran in 19.7s)

flutter test test/services/audiobookshelf/ test/modules/audiobookshelf/
→ 00:05 +40: All tests passed!

flutter test test/modules/more/ test/router/
→ 01:57 +94: All tests passed!

flutter test test/services/audiobookshelf/ test/modules/audiobookshelf/ test/modules/more/ test/router/
→ 02:15 +134: All tests passed!
```

New test breakdown (40):

- `audiobookshelf_client_test.dart` — 23: URL normalization, bearer header, ping without token, libraries parsing, pagination envelope/query, play-session payload and device id stability, item/track parsing, contentUrl and cover URL resolution (including base path prefix), progress payload, swallowed progress failures, 401/403/404/5xx/timeout/transport/malformed-JSON mapping.
- `audiobookshelf_settings_test.dart` — 6: empty/loaded state, save normalization, clear, real secure-storage round trip via the package's mock platform, half-written pair.
- `abs_playback_math_test.dart` — 6: locate/absolute position, clamping, empty and zero-duration books.
- `audiobookshelf_connection_screen_test.dart` — 5: empty/disabled actions, successful test names the account, rejected token shown, save persists normalized URL, stored credentials hydrate + disconnect.

Widget tests cover the connection screen only. The library and player screens depend on network images/media_kit platform channels and were kept out of widget tests; their pure logic (paging envelope, URL building, position mapping) is covered in Dart tests.

## Decisions

- English string literals in the new module and the one More tile; the 19 arb files were deliberately left untouched (l10n deferral).
- Non-book libraries are shown but dimmed and non-tappable rather than hidden, so a server does not look half-empty.
- `/audiobookshelf` shows setup until a server is saved, then the library; server settings is a second route pushed from the library app bar.
- The player uses one file at a time (no media_kit Playlist) so each chapter's seek/resume and per-file metadata are explicit.

## Known limitations

- No localization of the new strings (deferred).
- No offline downloads or caching.
- No dedicated progress-sync UI: progress is written best-effort; the only read-back is the playback session's resume position.
- Podcast libraries are listed but not playable.
- No background-audio/notification controls; playback is tied to the player screen's media_kit session.
- Cover requests rely on `?token=`; a 404 or network failure falls back to a placeholder icon.
- Plain HTTP is allowed by the existing Android (`usesCleartextTraffic="true"`) and Apple (`NSAllowsArbitraryLoads`) configuration, so LAN servers work without changes.
