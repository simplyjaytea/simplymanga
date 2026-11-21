# simplyMANGA — iOS CI operations review + proposal (Lane D-sign)

**2026-11-21 · moss · companion to SIDELOAD.md.**
`.github/workflows/ios.yml` is **parent-only** (WORKFLOW.md): Lane D does not edit it.
This document is (a) a verified assessment of the current pipeline, (b) a concrete
change **proposal** with a validated patch for the parent to apply, and (c) the ops
runbook for release-build handling. Nothing here was pushed; everything stayed local.

---

## 1. Current pipeline (read from the actual file, not memory)

`name: iOS build`, two jobs:

| | `check` | `build-ios` |
|---|---|---|
| Name | Analyze + test (Linux) | Unsigned .ipa (macOS) |
| Runner | `ubuntu-latest` | `macos-15` (arm64) |
| Timeout | 30 min | 90 min |
| Flutter | 3.50.1 stable (cached) | 3.50.1 stable (cached) |
| Steps | pub get → analyze → test | pub cache + CocoaPods cache → `rustup target add aarch64-apple-ios aarch64-apple-ios-sim` → pub get → `flutter build ios --release --no-codesign` → package IPA → upload |
| Dependency | — | **none — runs in parallel with `check`** |

- **Triggers:** push to `main` and pull requests, both **path-filtered**
  (`lib/`, `ios/`, `packages/`, `rust/`, `rust_builder/`, `assets/`, `pubspec.*`,
  the workflow itself) + `workflow_dispatch`. This already complies with the user's
  CI-trigger policy (relevant paths only; no gratuitous macOS runs). **No change proposed.**
- **Concurrency:** `ios-${{ github.ref }}`, `cancel-in-progress: true` — already present.
  **No change proposed.**
- **IPA packaging:** `mkdir Payload && cp -r build/ios/iphoneos/Runner.app Payload/ &&
  zip -qr simplyMANGA-unsigned.ipa Payload` at the **workspace root**.
- **Artifact:** `simplyMANGA-unsigned-ipa`, `retention-days: 14`, default compression,
  no `if-no-files-found` guard, upload step unnamed.
- **Mihon bridge probe (plan M5):** the `m_extension_server` pod embeds an OpenJDK Zero
  runtime fetched at pod-install time; the workflow comment documents the fallback
  (excise pod + stub `MihonExtensionService`). The verified run proves the probe passes.
- The workflow file is **unchanged since fork commit `2ea0a08`** — i.e. byte-identical
  to what produced the verified run below (`git diff cfe96b4 HEAD -- .github/workflows/ios.yml`
  is empty).

## 2. Verified evidence — run 44853126499

Re-verified read-only via `gh run view` / `gh api` on 2026-11-21 (not taken on faith
from the handoff):

| Fact | Value |
|---|---|
| Run | [44853126499][run], `iOS build`, event `push`, branch `main` |
| Commit | `cfe96b4396889ed730bd60a4d3e0c58cd2e79e78` |
| Created | 2026-11-21T01:57:09Z |
| Conclusion | **success** — both jobs green |
| `check` duration | 01:57:11 → 02:05:05 = **7 m 54 s** |
| `build-ios` duration | 01:57:11 → 02:07:32 = **10 m 21 s** |
| Started | **same second** → confirms no `needs` gate today |
| Artifact | `simplyMANGA-unsigned-ipa`, id 14687060592, 115,191,776 B, `expired: false` |
| IPA file | 115,637,609 B; SHA-256 `2d284ae9563fd619f823e01c7de488256bc8026bb11aba52c62e9ba5d5492f84` |
| Verdict | `verify_ipa.py`: **SIDELOAD-READY (unsigned)** — arm64, no FairPlay, no app-level signature/provision, bg modes `audio`+`fetch`, 53 frameworks (6 pre-signed: App, Flutter, OpenJDKRuntime, objective_c, qjs, subsampling_scale_image_view), 379 entries, 247.6 MB uncompressed |
| Artifact expiry | `expires_at = 2026-12-05T02:06:20Z` (14-day retention) |

[run]: https://github.com/simplyjaytea/simplymanga/actions/runs/44853126499

**Local vs remote:** local `main` (`bdb07c4`) is **5 commits ahead of `origin/main`
(`cfe96b4`), unpushed** — Lane A0/A1/A2, UI merge, FORK.md note. The artifact above
therefore predates the local engine/UI work. Pushing is the parent's call after review
(WORKFLOW.md §1); the next push to `main` touching filtered paths triggers a fresh build
automatically.

**Cost model:** public repo → Actions minutes free, including macOS. Still, macOS is the
scarce resource (~10.4 min per build vs ~7.9 min Linux); the proposal below avoids
spending it on code that fails the cheap checks.

## 3. Gap analysis → proposal

Four changes, one patch: [`ios.yml.patch`](ios.yml.patch) (apply from the app repo root
with `git apply docs/ios/ios.yml.patch`). Triggers, concurrency, runner, Flutter version,
retention: **untouched**.

| # | Change | Why |
|---|---|---|
| 1 | `build-ios: needs: check` | Today both jobs start simultaneously (evidence: identical start timestamps). A red analyze/test still burns ~10 macOS minutes. Gating costs ~8 min of wall-clock on green builds but saves the whole macOS job on red ones. For a sideload pipeline where every artifact is a potential test build, "no artifact from broken code" is the right trade. |
| 2 | `--build-number=$((1000 + github.run_number))` | Every CI build currently reports pubspec's static `130` — sideload tools and humans cannot distinguish builds by version. `1000 + run_number` is monotonic per workflow run and always above upstream's 130 (no version regression for overwrite-update detection). Marketing version stays `0.9.97`. Convention documented in SIDELOAD.md §8. |
| 3 | New step **Build provenance** → `build-info.json` + `SHA256SUMS`, uploaded as a second small artifact `simplyMANGA-build-info` | Run id, run number, run URL, commit, branch, bundle id, version, build, IPA SHA-256, build timestamp — available **without downloading 115 MB**. Mirrors the `build-info.json` the VPS fetcher already writes, so provenance exists from the moment of build. `SHA256SUMS` lets anyone verify the artifact after transfer. |
| 4 | Upload hardening: name the IPA upload step, `if-no-files-found: error` on both uploads, `compression-level: 0` on the IPA | A missing IPA currently uploads an empty/garbage artifact silently — `error` fails the job loudly. The IPA is already a zip; re-compressing wastes runner CPU for ~0.4% size difference (115.19 MB artifact vs 115.64 MB file). Provenance artifact stays small and separately retrievable. |

Also fixed in passing: the file lacked a trailing newline (the patch adds one).

**Deliberately not proposed:** trigger changes (already policy-compliant), concurrency
(already present), retention tuning (14 days is fine for a 7-day re-sign cadence),
scheduled rebuilds (user policy: no unrequested scheduled CI), self-hosted macOS
(no hardware need — public-repo minutes are free), signing in CI (D3: signing is
user-side with the free Apple ID; CI stays unsigned and secret-free).

### Patch validation (all performed locally, 2026-11-21)

- Anchors matched the **actual** current file exactly (3/3, single occurrence each).
- Proposed YAML parses (`yaml.safe_load`); `on:` triggers verified unchanged;
  `build-ios.needs == check`; new steps present.
- `bash -n` passes on **every** `run:` block of the proposed workflow (GitHub
  expressions stubbed), including the provenance heredoc.
- `git apply --check docs/ios/ios.yml.patch` → **exit 0** against the lane worktree.
- Patch applied to a scratch copy and re-parsed as YAML → OK.
- Worktree `.github/` confirmed **untouched** (`git status -s .github/` empty) —
  Lane D honours parent-only ownership.

**Parent action:** review, `git apply docs/ios/ios.yml.patch` on `main` (or cherry-pick
the change into the parent's integration commit), push when ready. First post-patch run
should show `build-ios` waiting for `check`, build `1000 + run_number`, and two artifacts.

## 4. Ops runbook (release-build handling)

**Trigger a manual build** (sanctioned `workflow_dispatch`; Moss does this on request):
```bash
gh workflow run ios.yml --repo simplyjaytea/simplymanga --ref main
gh run list --repo simplyjaytea/simplymanga --workflow ios.yml --limit 3
gh run watch <run-id> --repo simplyjaytea/simplymanga
```

**Fetch + verify the latest green build** (read-only):
```bash
python3 tool/ios/fetch_ci_ipa.py            # → /root/.local/share/simplymanga/ipa/run-<id>/
```
Writes `build-info.json` beside the IPA. `--run <id>` pins a run; `--force` re-downloads;
`--skip-verify` exists but should not be used for builds headed to a device.

**Artifact expiry:** retention is 14 days. `fetch_ci_ipa.py` refuses expired artifacts
with guidance; fix is a fresh dispatch (above), not archaeology. The run-44853126499
artifact expires ~2026-12-05.

**Reading a build:** `build-info.json` (fetcher-written today; CI-written once the patch
lands) is the provenance record: run id + commit + SHA-256 + version. Quote the run id
when reporting a device result — "0.9.97 (130)" alone is ambiguous until change #2 lands.

**Red build triage:** `check` red → Dart/Rust problem, lane-owned, no macOS spent (after
the patch). `build-ios` red with `check` green → iOS-specific: pod install (OpenJDK Zero
probe, plan M5 fallback documented in the workflow), cargokit/Rust target, Xcode/Flutter
version drift on the runner. Re-run once via `gh run rerun <id> --failed` before
escalating; runner image updates occasionally break cached toolchains.

**Ownership boundaries:** workflow edits = parent (this proposal is the route).
`tool/ios/**`, `docs/ios/**` = Lane D-sign deliverables (this branch). Signing material =
none in CI, none in the repo; the user's Apple ID lives only in their sideload tool.

## 5. Verification log (this lane, 2026-11-21)

| Check | Result |
|---|---|
| `tool/ios/tests/test_verify_ipa.py` | **22/22 OK** (synthetic IPAs: unsigned/signed/FairPlay/fat/corrupt/symlink/extensions/push-mode…) |
| Verifier vs real artifact | SIDELOAD-READY, exit 0, SHA-256 matches independent `sha256sum` |
| `fetch_ci_ipa.py --run 44853126499` (fresh dir) | download → verify → build-info.json, exit 0, identical SHA-256 |
| `fetch_ci_ipa.py` (latest-resolution + cache path) | resolved run 44853126499, cache hit, exit 0 |
| Proposal patch | `git apply --check` exit 0; YAML + `bash -n` clean; scratch apply OK; worktree workflow untouched |
| GitHub mutations by Lane D | **none** (read-only `gh api` / `gh run view` / `gh run download`) |
| Pushes | **none** — branch `lane/d-sign` local, per WORKFLOW.md |

Bugs found and fixed during verification (recorded so they stay fixed): Mach-O magic
endianness inversion in the first verifier draft (caught by unit tests before any real
artifact was judged), framework `_CodeSignature` path-index off-by-one, and the
workflow's missing EOF newline breaking naive patch generation.
