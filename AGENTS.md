# AGENTS.md — simplyMANGA app

Flutter foldable manga/novel reader with Audiobookshelf streaming, forked from
mangayomi. For current session state read `../STATUS-2026-11-22.md` (parent workspace).

## Repository topology

- This repo (`app/`) → `origin` = github.com/simplyjaytea/simplymanga (the user's fork).
  `upstream` = kodjodevf/mangayomi — **fetch only; never push or PR to upstream.**
- Parent workspace `..` holds specs (C1-SPEC, DENSITY-SPEC, PLAN), the P1 device
  protocol/runbook, `fixtures/`, `analysis/`, and per-lane worktrees (`../wt-*`).
- Work happens in lanes: one git worktree + branch per writer (`lane/<name>`), merged
  to `main` via PR or verified local merge. One owner per file; never two lanes in one tree.

## Toolchain

- Flutter: `export PATH=/root/.local/share/flutter/bin:$PATH`
- Rust sync server (`server/`): `cargo build --release` produces
  `libmangayomi_sync_server_native.so` — required before server tests run.
- GitHub CLI: always scope with `gh -R simplyjaytea/simplymanga`.

## Commands

- Analyze: `flutter analyze --no-pub`
- Full suite: `flutter test` (~6 min). Targeted fold + ABS:
  `flutter test test/core/fold test/services/audiobookshelf`
- iOS CI: `.github/workflows/ios.yml` — path-filtered to app-affecting files;
  test-only commits intentionally trigger no run (local full suite is their gate).
- IPA export: `python3 tool/ios/fetch_ci_ipa.py` (read-only — never triggers runs or
  pushes), then `python3 tool/ios/verify_ipa.py <path>`.

## Conventions (hard-won)

- TDD: regression test RED before the fix. Widget timing tests use `testWidgets` +
  `tester.pump` durations — this SDK's flutter_test does **not** export `fakeAsync`.
- Debounce/coalescing tests run on the fake clock, never wall-clock sleeps (load flake).
- Fold geometry: pure functions in `lib/core/fold/`; nested shells use last-report-wins
  completion. Posture is size-inferred until the Swift hinge channel lands (deferred).
- ABS: token lives in `flutter_secure_storage` only — never SharedPreferences, never
  logged. Reachability probe is public `/ping` (`/api/ping` 401s).
- iOS distribution decision D3: CI ships **unsigned** IPAs; the user re-signs with a
  free Apple ID via Sideloadly (`docs/ios/SIDELOAD.md`). No certificates in CI or repo.
- Device claims require screenshot AND log line (parent `P1-DEVICE-TRUTH-PROTOCOL.md`).
  Test content only on devices — no production accounts, credentials, or real library.

## Current state (2026-11-22)

- `main` @ `3373160`; full suite 1472 passed / 5 skipped / 0 failed; CI green at `e7ce8fd`
  (run 45028563306). C1a merged via PR #1 (`1078f38`); ABS slice merged (`cba9e03`).
- Open: D-C1-3 dead-band gesture (**not implemented — do not pass as done**), Swift
  hinge/posture channel, NIT-4 spread-rebuild caching, and the Duo device session.
- Kanban consolidated to 6 cards: `t_06cfa5c1` (scheduling), `t_1632e5dc` (device
  session), `t_73f2815b` (A3), `t_4b1f159c` (C1b), `t_6e0be9e9` (hinge), `t_4b99198a`
  (release gate). Do not create new cards without user direction.
