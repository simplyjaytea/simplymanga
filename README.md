# simplyMANGA

An iOS-first, foldable-native manga / anime / novel reader for the **iPhone
Duo** — designed to flow beautifully between the cover display and the inner
display, with a hardened anime playback pipeline.

> **Status: early development (Phase 0).** This is a derivative of
> [MangaYomi](https://github.com/kodjodevf/mangayomi) (Apache-2.0), forked at
> `da696dd` / v0.9.97. Upstream features are the baseline. See
> [FORK.md](FORK.md) for provenance and the exact change ledger.

## What this fork is for

1. **Anime that actually plays.** Upstream discards every playback error
   except one audio-decoder case, has no server fallback, and no timeouts on
   video extraction. We are building a real fallback state machine, pre-flight
   stream probing, per-extractor health tracking, and honest error states.
2. **Foldable-native UX.** Cover ↔ inner display continuity, crease-aware
   layout, and density tiers built for the Duo's two screens — not a phone UI
   stretched onto a tablet.
3. **Reader polish.** Manga and novel reading tuned for both displays.

## Building

iOS binaries are built by CI (`.github/workflows/ios.yml`): Linux runs
`flutter analyze` + `flutter test`; a macOS runner produces an **unsigned
`.ipa`** artifact. Flutter is pinned to **3.50.1** (Dart 3.14.0); all git
dependencies are pinned to exact commits.

```sh
flutter pub get
flutter analyze
flutter test
flutter build ios --release --no-codesign   # macOS only
```

### Installing on an iPhone (free Apple ID)

Unsigned CI artifacts must be re-signed before installation. With
[AltStore](https://altstore.io) or [SideStore](https://sidestore.io) and a free
Apple ID, apps re-sign automatically every 7 days. Distribution manifests and
signed releases arrive in a later phase.

## Licence

Apache-2.0, inherited from upstream. See [LICENSE](LICENSE) and
[FORK.md](FORK.md). Upstream's original README is preserved at
[docs/upstream-README.md](docs/upstream-README.md).