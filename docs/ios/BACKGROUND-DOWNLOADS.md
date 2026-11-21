# Background downloads — design & spike findings (PLAN M2, Lane D)

Task: `t_d0e0789f` (D-bg). Branch `lane/d-bg`. Status: **Dart half landed and
tested locally; iOS half delivered as validated parent-only proposals; device
measurement gated on P1.** Nothing pushed, no GitHub mutations, no device touched.

## 1. The problem

Downloads today run in Dart isolates (`DownloadIsolatePool`). When iOS suspends
the app, those isolates stop, so a download in flight stalls until the app is
foregrounded again. PLAN M2 asks for downloads that survive suspension.

The constraint that shapes the whole design: **the m3u8/HLS pipeline cannot be
backgrounded.** It parses the playlist, selects a variant, derives AES-128
key/IV, and orchestrates per-segment fetch + decrypt + merge *in Dart*. A
background `URLSession` can fetch bytes but cannot run that Dart logic. So M2
splits by content type rather than trying to background everything.

## 2. The split (decision)

| Content | Mechanism | Survives suspension? |
| --- | --- | --- |
| Direct files — manga pages, single-file MP4 episodes | native **background `URLSession`** | yes (system-managed) |
| m3u8 / HLS | **foreground** Dart pipeline + **per-segment resume** | no — resumes on next foreground |
| Opportunistic drain | **`BGProcessingTask`** (best-effort) | only when iOS grants time |

`BGProcessingTask` is *not* the download mechanism and *not* a guarantee. It
buys extra time to flush results and let pending transfers progress; iOS decides
if/when it runs. The background `URLSession` is what actually keeps direct-file
transfers alive.

## 3. Feasibility findings (grounded in the current tree)

- **HLS segment writes are already crash-safe.** `download_isolate_pool.dart`
  writes each segment to `TS_N.ts.part`, checks the decrypted length against
  `Content-Length` (L775–776), then `partial.rename(file.path)` (L791). Resume
  skips segments whose final file already exists and is non-empty.
- **…but resume had no provenance guard (the bug this lane fixes).** The temp
  directory is keyed only by `sha256(chapterId:m3u8Url)`. When a source rotates
  the playlist under the same URL — a different variant, fresh segment tokens, a
  shifted live window — the index-named `TS_1.ts` from the *old* playlist was
  kept and spliced into the *new* merge, corrupting the output. **Proven
  end-to-end** through the real isolate pool + a loopback HTTP server: the old
  code produced `[1,1,1,3,3,3]` where `[2,2,2,3,3,3]` was correct.
- **Direct-file writes are not staged.** Page downloads write straight to the
  target via `writeAsBytes` (L608), unlike the HLS `.part`→rename path. Moving
  these to a background session also moves the write into the system's staging
  area, which the reconciler then places atomically.
- **The existing Swift `background_task` channel is dormant.**
  `AppDelegate.swift` L63–99 implements `begin`/`end` around
  `UIApplication.beginBackgroundTask` (the ~30 s assertion), but **zero Dart
  callers** reference `com.kodjodevf.mangayomi.background_task`. It is not a
  background-download path and is left untouched by this proposal.
- **`Info.plist` declares only `audio` + `fetch`** background modes — no
  `processing`, no `BGTaskSchedulerPermittedIdentifiers`. Both are required for
  the `BGProcessingTask` half and are added by the proposal patch.

## 4. What landed locally (Dart, CI-testable, no device)

Two commits on `lane/d-bg`:

1. **`a1e212b` — HLS resume provenance guard.**
   `lib/services/download_manager/m3u8/resume_manifest.dart` fingerprints the
   resolved playlist (ordered segment URLs + AES-128 key/IV + media sequence)
   into `resume.json` in the temp dir. `M3u8Downloader.download()` calls
   `prepareHlsResume()` before filtering existing segments: a changed or unknown
   provenance discards stale `TS_N.ts`/`.part` files, then re-records the
   manifest. Unchanged playlists still resume without re-fetching.
   - 18 manifest unit tests + 2 end-to-end drift/resume tests (real isolate pool
     + loopback server). The drift test is the RED→GREEN proof of the splice fix.
2. **`a5e02a1` — background-session reconciliation contract.**
   `lib/services/download_manager/background/background_download_contract.dart`
   models the Dart↔native boundary for direct files: Dart registers requests
   (`taskId`/`url`/`destination`); the session reports per-task results; the
   reconciler places finished files and settles each task **exactly once**.
   Orphaned/duplicate reports are ignored; a completed report only counts once
   its staged file is moved (a move failure is a failure). Pure Dart,
   platform-agnostic. 8 unit tests.

Full `test/services/download_manager/` suite: **65 passing**, `flutter analyze`
clean on all touched files.

## 5. iOS proposal (parent-only — Lane D does not edit these directly)

Delivered under `docs/ios/`, mirroring the D-sign proposal-patch precedent:

- **`AppDelegate.swift.patch`** — adds `import BackgroundTasks`; registers the
  `BGProcessingTask` identifier in `didFinishLaunchingWithOptions`; wires a new
  `com.kodjodevf.mangayomi.background_download` method channel in
  `didInitializeImplicitFlutterEngine` to `BackgroundDownloadSession`.
- **`Info.plist.patch`** — adds `processing` to `UIBackgroundModes` and a
  `BGTaskSchedulerPermittedIdentifiers` array
  (`com.kodjodevf.mangayomi.background-download`).
- **`BackgroundDownloadSession.swift`** — reference implementation of the native
  half: background `URLSession` + delegate, a registry persisted across launches,
  staging dir, result reporting that matches `BackgroundDownloadResult`, and a
  best-effort `BGProcessingTask` drain.

**Both patches are validated to apply cleanly** (`git apply --check`) against the
current tree. **The Swift is a proposal, not compiled here** — this VPS has no
macOS/UIKit. The compile gate is the iOS CI build / P1 device session. The Dart
contract it implements against *is* tested, so the boundary semantics are pinned
even though the native code is uncompiled.

### Channel shape (`com.kodjodevf.mangayomi.background_download`)

Dart → native: `enqueue {taskId,url,destination,headers?}`, `cancel {taskId}`,
`pending`, `reconcile`, `acknowledge {taskId}`.
Native → Dart: `onResult {taskId,status,localPath?,error?}` where `status` ∈
`completed|failed|cancelled` — exactly `BackgroundDownloadResult`. Dart feeds
these into `BackgroundDownloadReconciler`, then calls `acknowledge` once a staged
file is placed so the staging copy is removed.

## 6. Risks & mitigations

- **Background execution is not guaranteed.** iOS may defer/kill transfers;
  `isDiscretionary=false` + `sessionSendsLaunchEvents=true` help but do not
  promise. Mitigation: the reconciler tolerates partial progress and the queue
  re-enqueues unfinished tasks on foreground. HLS already resumes per segment.
- **Free Apple ID sideload expiry (D-sign).** A sideloaded build is re-signed
  every ~7 days; a background session identifier tied to a re-installed bundle
  can orphan in-flight tasks. Mitigation: persisted registry + orphan-tolerant
  reconciliation; unfinished tasks re-enqueue rather than wedge.
- **Staging dir growth.** Completed-but-unacknowledged staged files accumulate.
  Mitigation: `acknowledge` removes them; reconcile-on-launch flushes pending
  reports; a future cleanup pass can prune stale staging entries.
- **Cross-volume move.** The staged file (Caches) and destination may differ;
  `MoveFile` is injected so the bridge can use a copy+delete fallback. The
  contract treats a failed move as a failure, never a silent completion.
- **Playlist drift.** Fixed by the provenance guard (§4.1); legacy temp dirs
  without a manifest are conservatively re-downloaded once.

## 7. Acceptance gates

| Gate | State |
| --- | --- |
| Dart resume + reconciliation tests green | **done** (65 passing, analyze clean) |
| Proposal patches apply cleanly | **done** (`git apply --check`) |
| Swift compiles in iOS CI | **pending** — CI/P1 (no macOS here) |
| Device measurement of background survival | **pending** — gated on P1 (see `P1-DEVICE-PROTOCOL.md`) |
| Parent applies iOS patches + Dart↔native wiring | **pending** — parent-owned integration |

## 8. Out of scope (follow-ups, not done here)

- Wiring `MDownloader`/`download_provider` to actually hand direct files to the
  native session (parent-owned integration; the contract is ready for it).
- The Dart `MethodChannel` client + `onResult` listener feeding the reconciler.
- Adding the new Swift file to the Xcode project / `project.pbxproj`.
- A staging-dir cleanup pass and retry/backoff policy for failed background tasks.