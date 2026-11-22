# Integration review findings — resolution notes

Companion to the disposition checklist triaged in Kanban `t_166ddac1`
(20 entries: 10 fix-now, 6 approved-deferral, 4 rejected/no-action).
This file carries the four documentation sub-items assigned to `t_2ddd9011`.
Code fixes landed in `lane/fix-fold` (merge `c2fe26d`) and `lane/afix1`
(merge `35a2e8e`); both are in `main`.

## MED-4 — curated sources: curated ≠ vetted-at-runtime

The curated repository list (`lib/services/curated_repositories.dart`) is a
set of hand-verified pointers, not a runtime trust guarantee:

- Curated addresses were verified by a human **at a point in time**. The
  indexes they point to are live and mutable; their contents can change
  after curation without any change to this app.
- Adding a curated repository uses the **same fetch path** as a manually
  entered URL (`getRepoInfosProvider`). Curation grants no elevated trust,
  no signature check, and no integrity pinning.
- There is **no auto-install**: every repository add is an explicit user
  action, and the add sheet shows a warning footer plus the per-row licence
  reported by the live index.
- `sourceCount` and licence fields in the curated list are hints that can
  drift from the live index; the live index is authoritative at add time.

Hardening (hash/signature pinning of indexes, re-surfacing licence from live
metadata, treating `sourceCount` as a drift signal) is an approved deferral.
It must land **before any auto-install or unattended source ingestion** is
added, or as part of a security review. Owner: gilfoyle.

## LOW-6 — design-literal ban boundary

The design-literal guard (`test/.../design_literals_test.dart`) scans
`lib/modules` only. Constants in `lib/core/fold` are **outside the token ban
by design**:

- `creaseBandWidth = 32` and related room/band geometry are structural
  geometry, not theming tokens.
- The 120 ms settle debounce is behaviour (Timer semantics), not a motion
  duration token.

No code change is intended here; this note records the boundary so a future
reader does not "fix" the exemption.

## E-02 — anime server-switch contract: < 2 s

Contract: when the open server stalls or fails, playback switches to the
next candidate server in **under ~2 seconds** from the stall being
detectable, rather than waiting on mpv's 5 s network timeout.

Implementation (`lib/modules/anime/mixins/anime_track_selection_mixin.dart`):

- A Dart **start watchdog** (~2 s) arms when a server open begins. If
  `playing=true` is not confirmed in time, the mixin reports a Timeout to
  the fallback engine and advances.
- The watchdog **cancels** on confirmed playing, **re-arms** for each
  fallback attempt, and is cleaned up on dispose (no late timeout).
- The Rust retry budget is bounded: `report_class` calls `machine.start()`
  before `on_error`, so every wired error counts an attempt
  (`MAX_ATTEMPTS = 2`, then advance/Fail). A dead server cannot be retried
  forever (E-01).

Regression tests: `test/modules/anime/mixins/anime_track_selection_mixin_test.dart`
("a stalled open reports a timeout at ~2s and falls back", "confirmed playing
cancels the watchdog", "dispose cleans the watchdog up", "two timeouts on one
server retry once then switch, not loop").

## E-09 — host ranking tie-break and default prior

Rust (`rust/src/engine/health.rs`) and Dart
(`lib/utils/host_health_mapping.dart`, `lib/models/host_health.dart`) share
one ranking contract:

- Score: EWMA with `ALPHA = 0.3`, neutral prior `successEwma = 0.5` on both
  sides (Dart row default aligned to the Rust neutral prior; previously 0).
- Ordering: score descending, then a **deterministic secondary key — host
  string ascending** — so equal-score hosts rank identically in Rust and
  Dart regardless of map iteration or sort stability.

Regression tests: `rank_ties_break_by_host_deterministically` (Rust) and
`test/modules/anime/utils/host_health_mapping_test.dart` (Dart parity).