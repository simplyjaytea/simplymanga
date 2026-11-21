# Fork provenance and Phase 0 ledger

simplyMANGA is a derivative of [MangaYomi](https://github.com/kodjodevf/mangayomi)
by kodjodevf, licensed Apache-2.0. Forked at commit `da696dd` (v0.9.97,
2026-11-20). The upstream licence and notices are preserved; see `LICENSE`.
Upstream's original README is kept at `docs/upstream-README.md`.

Goal: an iOS-first, foldable-native reader/player for the iPhone Duo —
cover display ↔ inner display, crease-aware layout, fold continuity — with a
hardened anime playback pipeline. Upstream features are the baseline; nothing
is removed without a recorded reason.

## Phase 0 changes (identity + reproducibility only, no behaviour changes)

| Change | Where | Why |
|---|---|---|
| Bundle id `com.kodjodevf.mangayomi` → `com.simplymanga.app` (incl. RunnerTests) | `ios/Runner.xcodeproj/project.pbxproj` | distinct app identity, sideloadable alongside upstream |
| Display name + permission strings → simplyMANGA | `ios/Runner/Info.plist` | branding |
| App title → simplyMANGA | `lib/main.dart` | branding |
| Update check → this repo's releases | `lib/modules/more/about/providers/check_for_update.dart` | a fork must not prompt users to install upstream builds over itself |
| Crash reports → this repo's issues | `lib/services/crash_report_issue.dart` | fork bugs belong to the fork |
| All 9 git dependencies + 2 git overrides pinned to exact commit SHAs | `pubspec.yaml` | upstream floats `master`/`main`/branch refs; a fork needs reproducible builds. SHAs taken from upstream's committed `pubspec.lock` |
| Upstream CI workflows deactivated | moved to `.github/workflows-upstream/` | they build upstream's release pipeline, not ours |
| New CI: path-filtered Linux analyze/test + macOS unsigned .ipa | `.github/workflows/ios.yml` | this VPS is Linux; iOS binaries come from CI |

## Phase 0 closure notes

- **media-kit override family:** the forked media-kit packages reference each
  other via git at HEAD inside their own pubspecs, so pinning only the root
  deps breaks pub version solving. All eight media-kit packages are pinned
  via `dependency_overrides` to one commit. Lockfile diff is metadata-only
  (ref strings + dependency labels); zero resolved-version changes.
- **MethodChannel names preserved:** `com.kodjodevf.mangayomi.volume_keys`
  and `.screen_brightness` must match the native registrars; they are
  protocol identifiers, not branding.
- **Test updated:** `test/services/crash_report_test.dart` asserted the
  upstream issues URL; updated to the fork (the only suite change).
- **Local gate results (2026-11-21):** `flutter analyze` — no issues (61 s);
  full `flutter test` — 1207 passed, 5 skipped, 1 failed (the URL assertion
  above, fixed and re-verified). clang 18 installed: `flutter_qjs`'s native
  build hook requires it on Linux (CI ubuntu runners ship it).

## Deliberately NOT renamed (compatibility)

- **Dart package name `mangayomi`** — 959 files import `package:mangayomi/…`;
  a rename is a mass rewrite with zero user value.
- **URL schemes `mangayomi://`, `mangayomi-sync://`** — tracker OAuth apps
  (AniList/Trakt/Simkl) are registered upstream with these callbacks. Renaming
  breaks tracker login until re-registration (planned Phase 5).
- **On-disk paths `Mangayomi/databases`, backup format identifiers, local-file
  scan folders** — renaming strands existing libraries and breaks backup
  restore compatibility.
- **`User-Agent: Mangayomi` in extractors** (e.g. dood) — host sites may key
  on it; changing it risks breaking sources.
- **AltStore source manifest `repo/source.json`** — deferred to Phase 6; a
  distribution manifest pointing at binaries we haven't built would be false.
- Discord RPC presence text, code comments referencing upstream — cosmetic,
  deferred.

## Toolchain

- Flutter **3.50.1** stable (Dart 3.14.0), pinned in CI and used locally.
- Rust core built via cargokit during `flutter build ios`; Go torrent server
  ships as the committed `go/torrent_server.xcframework` (no Go toolchain
  needed unless it is modified).