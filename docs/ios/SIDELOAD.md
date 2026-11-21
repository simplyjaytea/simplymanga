# simplyMANGA — iOS sideload runbook (free Apple ID, $0)

**Lane D-sign deliverable · 2026-11-21 · decision D3: free Apple ID, re-sign every 7 days, $0.**
Instructions are bundled with each test build per D3. This document is the signing half of
Lane D; it requires **no device to read** and was written without one. The first on-device
execution happens in the P1 user session (device-measurement work lives in D-bg).

> **Verification status.** Everything in §1 was measured from the real CI artifact
> (run [44853126499][run]) on 2026-11-21. Tool procedures in §§4–9 were checked against
> sideloadly.io and docs.sidestore.io on 2026-11-21. What has **not** happened yet: an
> actual install/refresh on the test iPhone. That is P1's job, not a gap in this document.

[run]: https://github.com/simplyjaytea/simplymanga/actions/runs/44853126499

---

## 0. The pipeline in one picture

```
 GitHub Actions (macos-15, free public-repo minutes)
   flutter build ios --release --no-codesign        ← unsigned, arm64
   zip → simplyMANGA-unsigned.ipa  (artifact, 14-day retention)
        │
        ▼  fetch (browser download, or tool/ios/fetch_ci_ipa.py on the VPS)
   verify_ipa.py  → SIDELOAD-READY (unsigned, no FairPlay, free-ID-compatible)
        │
        ▼  transfer to Giga PC (Windows) — browser download or Tailscale
   Sideloadly (primary)  /  SideStore (alternative)
   re-signs with YOUR free Apple ID → installs over USB/Wi-Fi
        │
        ▼  every ≤7 days
   auto-refresh daemon (Sideloadly)  /  tap "7 DAYS" in My Apps (SideStore)
```

The CI build is **unsigned on purpose**. Apple only lets the device owner's Apple ID
sign for that device, so signing happens on the user's side, not in CI. No certificates,
no $99 developer account, no server-side secrets.

## 1. The build you are installing (measured, not assumed)

| Property | Value |
|---|---|
| Artifact | `simplyMANGA-unsigned-ipa` from run 44853126499 (`main` @ `cfe96b4`) |
| File | `simplyMANGA-unsigned.ipa`, 115,637,609 bytes (artifact zip 115,191,776 B) |
| SHA-256 | `2d284ae9563fd619f823e01c7de488256bc8026bb11aba52c62e9ba5d5492f84` |
| Bundle ID | `com.simplymanga.app` |
| Version | 0.9.97 (build 130) — upstream pubspec version |
| Minimum iOS | **15.0** |
| Architecture | arm64 (device slice; no simulator fat binary) |
| Built with | Xcode 16.4 / iPhoneOS 18.5 SDK, Flutter 3.50.1, macos-15 runner |
| Signing state | **Unsigned at app level** — no `embedded.mobileprovision`, no app `_CodeSignature` |
| Background modes | `audio`, `fetch` only — **no push, no VoIP, no App Groups** |
| Entitlements | none declared (`ios/` contains no `.entitlements` file) |
| Frameworks | 53 bundles; 6 carry their own `_CodeSignature` — `App`, `Flutter`, `OpenJDKRuntime`, `objective_c`, `qjs`, `subsampling_scale_image_view`. Engine/plugin frameworks ship pre-signed — **normal**; re-signers replace these signatures with your Apple ID's. |

**Free-Apple-ID compatibility:** the app declares nothing that requires paid entitlements
(push, App Groups, associated domains, CarPlay…). A free account can sign it as-is.
The verifier (`tool/ios/verify_ipa.py`) re-checks all of this for every future build.

## 2. Free Apple ID — the rules Apple imposes

Verified against Sideloadly's FAQ (which quotes Apple's exact error strings) and SideStore docs:

1. **7-day validity.** A free-account signature expires after 7 days. The app then refuses
   to launch. **Data is not deleted** — re-signing with the same Apple ID revives it.
2. **3 sideloaded apps per device** (free profile). Error: *"This device has reached the
   maximum number of installed apps using a free developer profile."* Fix: remove another
   sideloaded app, or use a different Apple ID.
3. **10 App IDs per 7 days** per free account. Error: *"Your maximum App ID limit has been
   reached. You may create up to 10 App IDs every 7 days."* Fix: wait, or another Apple ID.
   Simply re-signing the **same bundle ID** does not burn a new App ID slot.
4. **No push entitlements.** simplyMANGA declares none, so this does not bite us.
5. **Overwrite = update, data preserved.** Same Apple ID + same bundle ID → the new IPA
   overwrites the old install *and keeps its documents/data*. Changing either the Apple ID
   or the bundle ID creates a **separate app with empty data**.
6. **Deleting the app deletes its data.** Expiry ≠ deletion; never "fix" an expired app by
   deleting it unless you intend to lose local data.

**Apple ID choice (recommended, not required):** use a *dedicated* free Apple ID for
sideloading rather than your main account. Any sideload tool handles your Apple ID
credentials to talk to Apple's signing servers; a dedicated account limits that exposure
and keeps your main account's 3-app / 10-App-ID quota untouched. SideStore explicitly
supports an account different from the one signed into the device. If the account has
two-factor authentication, keep a trusted Apple device nearby to read the verification
code during signing.

## 3. Pick your tool

| | **Sideloadly** (primary) | **SideStore** (alternative) |
|---|---|---|
| What it is | Desktop app (Windows/macOS) that signs + installs IPAs | On-device AltStore fork; PC needed only once |
| Weekly refresh | Automatic daemon on Giga PC (PC must be on, same Wi-Fi) | Tap "7 DAYS" in SideStore → My Apps, **on the phone itself** |
| Windows prerequisite | **Web versions** of iTunes + iCloud (uninstall Microsoft Store versions first) | iTunes from Apple *or* Microsoft Store (Apple direct recommended); 64-bit Windows only |
| Extra moving parts | Bonjour service for Wi-Fi refresh | LocalDevVPN app (must be connected to install/refresh) + pairing file |
| Known fragility | PC off / asleep at expiry → manual refresh needed | Pairing file can expire after iOS updates/resets *or at random* (Apple's doing) → re-import via iloader |
| Best when | Giga PC is regularly on and on the same Wi-Fi as the iPhone | The iPhone should refresh itself without depending on the PC |

**Recommendation:** start with **Sideloadly** for the P1 session (simplest path: drag IPA,
enter Apple ID, press Start; the USB cable is already there). If keeping Giga PC awake for
weekly refreshes proves annoying, migrate to SideStore — the IPA and Apple ID carry over
unchanged. Both consume the same unsigned artifact; nothing in CI is tool-specific.

## 4. One-time prerequisites

**On Giga PC (Windows):**
1. Install **web-version iTunes** and **web-version iCloud** from Apple's site (Sideloadly
   links them on its homepage). If the Microsoft Store versions are installed, **uninstall
   them first** — Sideloadly will not see the device otherwise.
2. Install Sideloadly (v0.71.0 at time of writing; Windows 7+, 64- or 32-bit) from
   <https://sideloadly.io/>.
3. For Wi-Fi refresh later: Apple's **Bonjour** service may be needed (it ships with web
   iTunes). The first sideload must be over **USB** — that pairing is what enables Wi-Fi.

**On the test iPhone:**
1. iOS **15.0 or newer** (the app's minimum; SideStore also requires 15.0+). A passcode
   must be set (SideStore requirement; good practice regardless).
2. **Developer Mode** (iOS 16+): Settings → Privacy & Security → Developer Mode → on →
   restart. Without it, sideloaded apps will not install/launch.
3. When first connected to Giga PC: tap **Trust** on the "Trust This Computer?" prompt and
   enter the passcode.

**Apple ID:** create/pick the dedicated free Apple ID (§2). No developer enrollment, no
payment, no certificates to manage — the tool registers a free provisioning profile
automatically.

## 5. Get the IPA

**User path (simplest, no VPS access needed):** the repo is public.
1. Open the latest green **iOS build** run:
   <https://github.com/simplyjaytea/simplymanga/actions/workflows/ios.yml>
2. Scroll to **Artifacts** → download `simplyMANGA-unsigned-ipa` (a ~115 MB zip).
3. Extract it → `simplyMANGA-unsigned.ipa`. (GitHub wraps artifacts in a zip; the IPA
   inside is the real file.)
4. Note the run number/date so you know which build you hold. Artifacts expire after
   **14 days** — if the link is gone, ask Moss to trigger a fresh build (§10 / CI-OPS.md).

**Moss path (VPS, read-only against GitHub):**
```bash
cd /root/projects/gilfoyle/simplyMANGA/app   # or any lane worktree
python3 tool/ios/fetch_ci_ipa.py             # latest green main build → verify → provenance
# cache: /root/.local/share/simplymanga/ipa/run-<id>/{simplyMANGA-unsigned.ipa,build-info.json}
```
The fetcher resolves the latest successful `ios.yml` run on `main`, checks artifact
expiry, downloads, SHA-256s, runs the verifier, and writes `build-info.json` (run id,
commit, version, hash). It never triggers runs or mutates GitHub state.

**Transfer to Giga PC:** browser download directly on Giga PC is the default. From the
VPS, any Tailscale-reachable share/scp works too — the file is not secret (it is an
unsigned public-repo build), but prefer authenticated channels as a matter of habit.

## 6. First install (Sideloadly, USB)

1. Connect the iPhone to Giga PC with a **data-capable USB cable**. Open iTunes once and
   confirm the device appears (this proves the web iTunes/iCloud stack works). Tap Trust
   on the phone if prompted.
2. Open Sideloadly. The device should appear in the device dropdown. If it says
   *no devices detected*: reinstall web iTunes/iCloud, reboot, try another cable/port
   (see §10).
3. **Drag `simplyMANGA-unsigned.ipa`** onto the Sideloadly window.
4. Enter the **free Apple ID** (and password). Have a trusted Apple device ready for the
   2FA verification code if prompted.
5. Advanced options — leave defaults, except confirm:
   - **Bundle ID stays `com.simplymanga.app`** (do not suffix it; a changed bundle ID
     breaks overwrite-updates and burns an App ID slot).
   - **Automatic refresh enabled** for this app (default).
6. Press **Start**. Sideloadly registers the free App ID, signs the app and all 53
   frameworks with your Apple ID's provisioning profile, and installs. First run can take
   a few minutes; watch the installation log if it stalls.
7. On the iPhone: Settings → General → **VPN & Device Management** → under *Developer App*
   tap your Apple ID → **Trust**. (iOS wording varies slightly by version.)
8. Launch simplyMANGA from the home screen. Done — the clock starts now: **7 days**.

## 7. Keeping it alive (the 7-day cycle)

**Automatic (Sideloadly daemon):** with auto-refresh enabled, Sideloadly re-signs enrolled
apps before they expire, provided:
- Giga PC is **on and awake** (not asleep/shut down) near the expiry moment,
- the iPhone is reachable: **same Wi-Fi network** (after the first USB pairing; Bonjour
  installed) **or** plugged in via USB,
- the same Apple ID credentials are saved in Sideloadly.

If the PC was off and the app expired: the app icon stays, data stays, launch fails.
Plug in the phone (or get both on the same Wi-Fi), open Sideloadly, and sideload the
**same IPA with the same Apple ID again** — it overwrites and revives, data intact.

**Manual weekly ritual (fallback):** once a week, drag the same IPA → same Apple ID →
Start. Two minutes, USB or Wi-Fi.

**SideStore route (if migrated):** open LocalDevVPN → Connect → SideStore → My Apps →
tap the **7 DAYS** counter next to simplyMANGA (and next to SideStore itself — it is a
sideloaded app too). If prompted to revoke/create a signing certificate, accept
(*Yes* / *Refresh Now*). No PC involved.

## 8. Updating to a newer CI build

1. Fetch the new artifact (§5). Check `build-info.json` / the run page: newer run id,
   newer commit. (CI build numbers are `1000 + run_number` once the CI-OPS proposal
   lands; until then every build reports pubspec's `130` — identify builds by **run id +
   commit**, not the version string.)
2. Sideloadly: drag the new IPA, **same Apple ID, same bundle ID**, auto-refresh on →
   Start. It overwrites the previous install **and keeps data** (Sideloadly FAQ confirms
   overwrite semantics, including for apps enrolled in the refresh daemon).
3. SideStore: My Apps → refresh/update with the new IPA via the same account.
4. Launch and confirm the app behaves. If a build misbehaves, the previous IPA is still
   in the VPS cache (`run-<id>/`) — reinstall it the same way to roll back.

## 9. SideStore alternative (full procedure)

Checked against docs.sidestore.io (installation/prerequisites + install), 2026-11-21.

**Prerequisites:** iPhone with passcode on iOS 15.0+; a computer for the *initial* install
only (Windows 8+ **64-bit** — 32-bit and Windows-10-on-ARM are unsupported); iTunes from
Apple directly (recommended) or Microsoft Store, or the Apple Devices app; **Wi-Fi**
(cellular is not suitable); **LocalDevVPN** installed from the App Store.

**On Giga PC:**
1. Install **iloader** (MSI recommended) from the SideStore docs' Windows page.
2. Connect the iPhone via USB; trust the computer; enter passcode.
3. Open iloader → sign in with the Apple Account (need not be the device's account;
   **case-sensitive**) → select the device → **Install SideStore (Stable)**.

**On the iPhone:**
1. Settings → General → VPN & Device Management → Developer App → your Apple Account →
   **Trust**.
2. iOS 16+: Settings → Privacy & Security → **Developer Mode** on → restart.
3. Open **LocalDevVPN** → **Connect** (allow VPN configuration; passcode). The VPN must be
   connected any time you install, update, or refresh apps in SideStore.
4. Open SideStore → sign in with the **same** Apple Account used in iloader.
5. My Apps → tap the **7 DAYS** counter next to SideStore to refresh it and finish setup.
   Accept any certificate revoke/create prompt.
6. Install simplyMANGA's IPA through SideStore (My Apps → + / sideload), then refresh it
   the same way weekly.

**Caveat (documented, not folklore):** the pairing file SideStore relies on **may expire
when you update or reset iOS — and at random times because of Apple's software**. Symptom:
refreshes/installs fail with pairing errors. Fix: re-import the pairing file via iloader
(the docs link a guide from the install page). This fragility is exactly why Sideloadly
is the primary recommendation.

## 10. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Sideloadly: *no devices detected* | Store-version iTunes/iCloud, bad cable, untrusted computer | Uninstall Store versions → install **web** iTunes + iCloud → reboot → open iTunes with device connected → tap Trust → try another cable/port |
| iPhone: *Untrusted Developer* on launch | Developer profile not trusted | Settings → General → VPN & Device Management (Profiles on older iOS) → tap the Apple ID used → Trust |
| Install fails on iOS 16+ | Developer Mode off | Settings → Privacy & Security → Developer Mode → on → restart |
| *Maximum App ID limit… 10 App IDs every 7 days* | Apple free-account quota | Wait a few days or use another Apple ID; keep the bundle ID stable to avoid burning slots |
| *Maximum number of installed apps using a free developer profile* | 3-app free limit | Remove another sideloaded app or use another Apple ID |
| App won't launch after ~a week | 7-day signature expired | Re-sideload same IPA + same Apple ID (data intact). Do **not** delete the app |
| Wi-Fi refresh never happens | PC asleep/off, different network, no Bonjour, no prior USB pairing | Wake PC, same Wi-Fi, install Bonjour, do one USB sideload to pair |
| SideStore refresh fails after iOS update (or randomly) | Pairing file expired | Re-import pairing file via iloader |
| SideStore install/refresh does nothing | LocalDevVPN not connected | Open LocalDevVPN → Connect, retry |
| Artifact download link gone | 14-day retention expired | Trigger a fresh build: `gh workflow run ios.yml --repo simplyjaytea/simplymanga --ref main` (Moss, on request) |
| Update installed but data empty | Bundle ID or Apple ID changed | Reinstall with the **original** Apple ID + `com.simplymanga.app`; the old data lives in the old install |

## 11. Honesty boundary

- **Verified here:** CI green (both jobs), artifact bytes + SHA-256, unsigned state,
  free-ID-compatible configuration, tool procedures against vendor docs, fetch/verify
  tooling against the real artifact (22 unit tests + end-to-end).
- **Not verified here:** actual signing/install/refresh on the test iPhone — no device in
  this lane. First execution: **P1 user session**; background-download measurements:
  **D-bg**. If reality contradicts this runbook, the runbook gets patched, not the facts.
- Apple's free-provisioning quirks (anisette/2FA prompts, occasional signing-server
  errors) are account-side and can vary; the troubleshooting table covers the documented
  cases. Sideloadly's optional *Remote Anisette* transmits only IP/OS/version to its
  server (per its FAQ); local anisette is the default.

## 12. Phase 6 distribution — deferred, do not publish yet

PLAN Phase 6 (AltStore/SideStore **source** publishing via `repo/source.json`) is
deferred. The fork's `repo/source.json` still describes **upstream mangayomi**, not
simplyMANGA — publishing it as-is would point users at the wrong app. Until Phase 6:
manual IPA sideload per this runbook is the distribution channel. Lane D owns neither
the decision to publish nor the manifest rewrite; flagged here so nobody sideloads the
wrong feed by accident.

---

### Appendix A — Moss operations (VPS)

```bash
# fetch + verify latest green build (read-only; never triggers CI)
python3 tool/ios/fetch_ci_ipa.py
# specific run / fresh download / custom cache
python3 tool/ios/fetch_ci_ipa.py --run 44853126499 --force --out /tmp/ipa
# verify any IPA by hand
python3 tool/ios/verify_ipa.py <file.ipa> --expect-bundle-id com.simplymanga.app
# unit tests
python3 tool/ios/tests/test_verify_ipa.py
```
Cache root: `/root/.local/share/simplymanga/ipa/run-<id>/` (IPA + `build-info.json`).
GitHub access is `gh` as `simplyjaytea`; all Lane D tooling is **read-only** against
GitHub — pushes and workflow edits belong to the parent (WORKFLOW.md).

### Appendix B — sources

- Sideloadly homepage + FAQ (v0.71.0), fetched 2026-11-21: <https://sideloadly.io/>,
  <https://sideloadly.io/faq> — 7-day/free limits, auto-refresh daemon, Wi-Fi pairing,
  web iTunes/iCloud requirement, overwrite semantics, Developer Mode, trust flow.
- SideStore docs, fetched 2026-11-21:
  <https://docs.sidestore.io/docs/installation/prerequisites>,
  <https://docs.sidestore.io/docs/installation/install> — iloader flow, LocalDevVPN,
  7 DAYS refresh, pairing-file expiry, Windows iTunes guidance.
- CI evidence: run 44853126499 (`gh run view` / `gh api`, read-only) + artifact
  dissection (`zipfile`/`plistlib`/Mach-O parse) — see CI-OPS.md §2.
