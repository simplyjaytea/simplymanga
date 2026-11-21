# P1 device protocol — background-download measurement

**Gated on the P1 user session.** This half cannot run on the VPS (no device, no
macOS). It is the acceptance measurement for the iOS proposal in
`BACKGROUND-DOWNLOADS.md`. Run it on a real iPhone with the parent-applied
patches + a build that includes `BackgroundDownloadSession.swift`.

## 0. Preconditions

- Parent has applied `AppDelegate.swift.patch` + `Info.plist.patch`, added
  `BackgroundDownloadSession.swift` to the Runner target, and wired the Dart
  `background_download` client + `onResult` listener to
  `BackgroundDownloadReconciler`.
- Build succeeds in iOS CI (the Swift compile gate). Install on device (sideload
  per `wt-dsign/docs/ios/SIDELOAD.md` or a dev build).
- A test source serving: (a) a direct multi-MB file (single-file MP4 episode or a
  large page), and (b) an HLS playlist with ≥ 20 segments. A local loopback
  server on the tailnet works; record its URL.
- Console.app (or `idevicesyslog`) attached to the device, filtered to the app
  process, to capture `os_log`/print timing. Add temporary `os_log` timestamps in
  `enqueue`, `didFinishDownloadingTo`, `didCompleteWithError`, and `onResult`.

## 1. Scenarios

### S1 — Direct file survives suspension (the core M2 claim)
1. Foreground: enqueue a direct file large enough to take ≥ 60 s on the test
   network (throttle if needed). Confirm `enqueue` returns and the task starts.
2. After ~5 s, press Home / swipe to background the app. **Do not force-quit.**
3. Leave backgrounded ≥ 90 s (longer than the ~30 s `beginBackgroundTask` grace,
   to prove the *background session*, not the assertion, is doing the work).
4. Foreground the app.
- **Measure:** did `didFinishDownloadingTo` fire while backgrounded (timestamp
  before foreground)? Was `onResult{completed}` delivered and the file placed at
  its destination by the reconciler? Final file size == `Content-Length`?
- **Pass:** file completes and is placed without the app having been foreground
  during the transfer. **Fail:** transfer only progresses after foregrounding
  (means it fell back to the Dart isolate path, not the background session).

### S2 — Force-quit then relaunch (session outlives the process)
1. Enqueue a direct file, background, then **force-quit** the app mid-transfer.
2. Relaunch after ≥ 30 s.
- **Measure:** does `session.getAllTasks` re-attach the in-flight task on
  `attach`? Does the registry restore? Does the transfer complete and reconcile?
- **Pass:** re-attach + completion, or a clean re-enqueue (no wedge, no duplicate
  placement). **Fail:** orphaned task that never settles, or a double-placed file.

### S3 — HLS resumes per segment across suspension (foreground half)
1. Foreground: start an HLS download (≥ 20 segments). Let ~half complete.
2. Background ≥ 60 s (Dart isolates suspend), then foreground.
- **Measure:** are already-complete `TS_N.ts` files reused (no re-fetch — check
  server hit counts)? Does the download finish from where it stopped?
- **Pass:** completes; completed segments fetched exactly once across the whole
  run. **Fail:** re-fetches complete segments, or stalls.

### S4 — Playlist drift on resume (the provenance guard, on device)
1. Start an HLS download; let ≥ 1 segment complete; interrupt (background long
   enough to suspend, or kill).
2. Rotate the server playlist to new segment URLs/content under the **same**
   m3u8 URL.
3. Resume.
- **Measure:** is the stale `TS_1.ts` discarded (server re-fetches segment 1)?
  Is the merged output pure new-playlist content (no splice)?
- **Pass:** clean re-download of changed segments; correct merge. **Fail:** old
  segment bytes appear in the output. (This is the device confirmation of the
  Dart RED→GREEN proof already landed in `a1e212b`.)

### S5 — BGProcessingTask drain (best-effort, not guaranteed)
1. Enqueue several direct files, background, lock the device, leave ≥ 15 min
   (ideally on power + Wi-Fi to favour scheduling).
2. Observe whether iOS grants a processing window.
- **Measure:** does `handleProcessingTask` run (log)? Does it flush pending
  results / reschedule? 
- **Pass (soft):** when granted, it drains and reschedules cleanly; expiration
  cancels without crash. **Not a failure if iOS never grants it** — this task is
  best-effort by design. Record grant frequency over ≥ 3 trials as evidence, not
  a gate.

## 2. Metrics to record (per scenario)

- Wall-clock: enqueue → completion; backgrounded duration; foreground events.
- Server hit counts per segment URL (proves resume reuse / drift re-fetch).
- Final file byte length vs `Content-Length`; merge correctness (checksum or
  playable output).
- `onResult` status sequence; reconciler summary (completed/failed/cancelled/
  orphaned); any duplicate placement.
- Whether completion occurred while backgrounded (S1/S2 key signal).

## 3. Acceptance

- **Hard gate:** S1 passes (direct file completes while backgrounded) and S3/S4
  pass (HLS resume + drift correctness on device). S2 must not wedge or
  double-place.
- **Soft evidence:** S5 grant behaviour recorded; absence of grants is acceptable.
- Capture logs + a short results table back into the task thread. If S1 fails
  because iOS refuses background execution for the sideloaded bundle, record the
  exact behaviour and re-scope (the Dart resume half still stands on its own).

## 4. Safety

- No production accounts/credentials on the test build; use the loopback/tailnet
  test source.
- Do not modify the user's device beyond installing the test build; note the
  sideload expiry (D-sign ~7-day re-sign) when scheduling long trials.