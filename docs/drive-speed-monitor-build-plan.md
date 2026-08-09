# Drive Speed Monitor — Incremental Build Plan

**Version:** 0.1
**Date:** August 9, 2026
**Companion to:** `drive-speed-monitor-requirements.md` (v1.0)
**Approach:** Small, verifiable increments. Each one has a single goal, a concrete build step, and a way to confirm it works before moving on. We do not start an increment until the previous one is verified.

---

## How to read this

Each increment lists:

- **Goal** — the one thing this step proves.
- **Build** — what gets added.
- **Verify** — the observable check that it works.
- **Done when** — the pass condition.

Requirement IDs (FR-#, NFR-#) reference `drive-speed-monitor-requirements.md`.

**Division of labor** (per the established NetSpeed workflow): Claude verifies logic headlessly with `swiftc`/`xcodebuild` and reports; Chris runs the GUI in Xcode and confirms. One increment at a time.

**Generating disk load for testing.** A read test that reliably moves the needle:

```bash
dd if="/Volumes/1TB_Samsung/Important_Docs.dmg" of=/dev/null bs=1m count=2000
```

This measured **740 MB/s** on the 1 TB 990 EVO Plus during prototyping. For writes, write to a scratch file on the drive under test and delete it afterwards. A large Finder copy from the internal SSD to a USB drive exercises read and write on both buses at once.

**Starting point.** Unlike NetSpeed, this project does not start from an empty Xcode project. `drive-speed-monitor/` is a working copy of NetSpeed v1.0 — a complete, shipped app. Phase 0 re-badges it, Phase 1 replaces the measurement core, Phase 2 adjusts the UI to the new units and vocabulary, and **Phases 3 and 4 are inherited intact** and only need verifying. The work concentrates in Phases 0, 1, 2, and 5.

---

## File change map

| File | Disposition |
|---|---|
| `NetworkCounters.swift` | **Replaced** by `DriveCounters.swift` — full rewrite, IOKit instead of `getifaddrs` |
| `SpeedSampler.swift` | **Substantial edit, net simpler** — new counter source, bus filter, three-scalar diff, MB/s math. Loses `lastByName`, `activeInterfaces`, and `sourceText` |
| `SpeedHistory.swift` | **Field rename** — `downMbps`/`upMbps` → `readMBps`/`writeMBps` |
| `ReadoutFormat.swift` | **Small edit** — `intDigits` 3 → 4 (FR-6) |
| `SpeedReadout.swift` | **Edit** — Down/Up → Read/Write, drop the dual-unit parenthetical (FR-5) |
| `SpeedChart.swift` | **Small edit** — axis unit `Mbps` → `MB/s`, legend Download/Upload → Read/Write |
| `SpeedPalette.swift` | **Comments only** — blue/red mapping carries over unchanged |
| `ContentView.swift` | **Edit** — remove the source-caption `Text` and its `HStack`/`Spacer`; the sampling menu becomes the whole bottom row. Help text reworded |
| `NetSpeedApp.swift` | **Renamed** to `DriveSpeedApp.swift`, struct and window title renamed |
| `Assets.xcassets/AppIcon` | **New artwork** — speedometer icon is NetSpeed's |
| `design/icon.svg`, `gen_icon.py` | **New artwork** source |
| `docs/network-*.md` | **Superseded** — remove or archive (decide in 0.2) |
| `README.md` | **Rewrite** |
| `NEXT-SESSION-HANDOFF.md` | **Review** — NetSpeed session state, likely stale |
| `LICENSE` | **Keep** |

---

## Phase 0 — Project identity

### Increment 0.1 — Rename NetSpeed → DriveSpeed  ✅ COMPLETE (Aug 9, 2026)
- **Goal:** A buildable, correctly-badged `DriveSpeed` app that still behaves exactly like NetSpeed. Measurement is untouched — this increment changes names only, so any later breakage is unambiguously Phase 1's.
- **Build:** Rename directories `NetSpeed/` → `DriveSpeed/` and `NetSpeed/NetSpeed/` → `DriveSpeed/DriveSpeed/`; `NetSpeed.xcodeproj` → `DriveSpeed.xcodeproj`; `NetSpeed.xcscheme` → `DriveSpeed.xcscheme`. In `project.pbxproj`: target name, product reference, group paths, and `PRODUCT_BUNDLE_IDENTIFIER` → `com.arc3solutions.DriveSpeed`. Rename `NetSpeedApp.swift` → `DriveSpeedApp.swift` and `struct NetSpeedApp` → `DriveSpeedApp`, including the FR-18 window-title fallback strings. Claude does this headlessly (Chris's call, Aug 9).
- **Verify:** `xcodebuild -project DriveSpeed.xcodeproj -scheme DriveSpeed build` succeeds warning-free; then Chris opens it in Xcode and runs it. Window title reads **"DriveSpeed 1.0"**. Because the bundle ID changed, the window appears top-left on this first run (FR-13) rather than at NetSpeed's remembered position — that is the expected, correct signal that the re-badge took.
- **Done when:** Clean `xcodebuild`, app launches from Xcode, title correct, still showing live *network* numbers.
- **Result (Aug 9, 2026):** Renamed `NetSpeed/` → `DriveSpeed/`, `NetSpeed/NetSpeed/` → `DriveSpeed/DriveSpeed/`, `NetSpeed.xcodeproj` → `DriveSpeed.xcodeproj`, `NetSpeed.xcscheme` → `DriveSpeed.xcscheme`, and `NetSpeedApp.swift` → `DriveSpeedApp.swift` (`struct NetSpeedApp` → `DriveSpeedApp`, both FR-18 title strings). All 26 `NetSpeed` occurrences across `project.pbxproj`, the scheme, and the Swift file headers replaced; `grep -rn NetSpeed` over the project now returns nothing. Stale `xcuserdata/` directories deleted (gitignored, Xcode regenerates them) so no orphaned `NetSpeed.xcscheme` entry lingers in the scheme manager. `xcodebuild -project DriveSpeed.xcodeproj -scheme DriveSpeed -configuration Debug clean build` → **`** BUILD SUCCEEDED **`**, with no compiler warnings (the only emitted warning is the benign `appintentsmetadataprocessor` "No AppIntents.framework dependency found", which NetSpeed also emitted). Built bundle verified: `CFBundleIdentifier` = `com.arc3solutions.DriveSpeed`, `CFBundleName`/`CFBundleExecutable` = `DriveSpeed`, `CFBundleShortVersionString` = `1.0` (so FR-18 renders **"DriveSpeed 1.0"**), `LSMinimumSystemVersion` = `26.0`, and `com.apple.security.app-sandbox` still present in the signed entitlements. Measurement code deliberately untouched — `NetworkCounters.swift` keeps its name until Increment 1.1 replaces it. **Confirmed in Xcode by Chris (Aug 9, 2026):** all four checks passed — title reads "DriveSpeed 1.0", the window opened top-left (the expected consequence of the new bundle id having no saved frame), the numbers still tracked live network activity, and closing the window quit the app.

### Increment 0.2 — Reset git and prune inherited artifacts  ✅ COMPLETE (Aug 9, 2026)
- **Goal:** A clean repository with no path back to `netspeed-macos`.
- **Build:** Delete `.git` and re-init; no remote (Chris's call, Aug 9 — a remote gets added only when he's ready to publish). Retire the two `network-*.md` docs from `docs/`. Review `NEXT-SESSION-HANDOFF.md` and `README.md` for NetSpeed-specific content.
- **Verify:** `git remote -v` is empty; `git log` shows a single initial commit; `grep -ri netspeed` returns only intentional lineage references in the requirements doc.
- **Done when:** Clean repo, no accidental route to the NetSpeed remote. **⚠️ Must land before any commit** — the duplicated folder carried NetSpeed's three commits and pushed to `github.com/chrisARC3/netspeed-macos`.
- **Result (Aug 9, 2026):** Before deleting anything, confirmed the originals were intact: `network-speed-monitor/` still holds all three NetSpeed commits and both `network-*.md` docs, and the remote holds them too — so nothing unique was lost. Deleted `.git` and re-initialised on `main` with a single commit, **no remote configured**. Removed the two inherited `network-*.md` docs and `docs/screenshot.png` (it depicted NetSpeed's network readout, so it would have misrepresented this app). Rewrote `README.md` for DriveSpeed with an explicit in-development status block, and rewrote `NEXT-SESSION-HANDOFF.md`, which was badly stale — it described NetSpeed at end of Phase 2, pointed at the old paths, and would have steered a future session into NetSpeed's Increment 3.1. Also corrected the `design/gen_icon.py` docstring, the last unintentional NetSpeed reference. Verified: `git remote -v` empty, `git log` one commit on `main`, working tree clean, 32 files tracked, and `grep -ril netspeed` returns only `README.md` plus the two docs — all deliberate lineage prose.
- **⚠️ Open item — app icon.** The file change map lists new artwork for `Assets.xcassets/AppIcon` and `design/icon.svg`, but **no increment covers it**. The inherited artwork is a speedometer, which arguably reads as "speed" regardless of bus and may need no change at all. Chris's call: keep it as-is, or add an increment to regenerate. `docs/speedometer.png` is untouched — gitignored, unused, rights unverified.

---

## Phase 1 — Core measurement (console only, no UI change yet)

### Increment 1.1 — Read block-storage byte counters once
- **Goal:** Prove we can read cumulative bytes read/written per physical device. (FR-8)
- **Build:** New `DriveCounters.swift` replacing `NetworkCounters.swift`. Enumerate `IOServiceMatching("IOBlockStorageDriver")`; per device read the `Statistics` dictionary for `Bytes (Read)` / `Bytes (Write)` plus `Physical Interconnect`. BSD name and product name are read **in this increment only**, to make the console output legible; per FR-10d they do not survive into the shipped sampler.
- **Verify:** Console prints one row per physical disk with large, plausible byte counts and a correct bus string.
- **Done when:** Non-zero counters print for the internal SSD and each attached external.
- **Note:** Already prototyped and validated headlessly on Aug 9 — 5 devices found, internal `Apple Fabric` at R=245.6 GB / W=153.0 GB, four externals on `USB`. **Sandbox confirmed** (NFR-2): the same code ran from a signed `.app` with `com.apple.security.app-sandbox` and no entitlement exceptions. Chris still confirms in Xcode.

### Increment 1.2 — Poll on a timer and compute MB/s
- **Goal:** Turn raw counters into live read/write throughput. (FR-4, FR-5, FR-8)
- **Build:** Point `SpeedSampler` at `DriveCounters`. Per tick compute `(bytesNow − bytesLast) ÷ elapsed ÷ 1_000_000` for read and write. Print `R X.X MB/s  W X.X MB/s`. Retain the `now < last` guard (harmless; covers device re-enumeration resets — the 32-bit wrap NetSpeed fought does not apply, these counters are 64-bit).
- **Verify:** Run the `dd` read test above; the read figure climbs and settles, then drops to ~0. Cross-check against Activity Monitor's Disk tab.
- **Done when:** Console figures track real I/O and read ~0 when idle.

### Increment 1.3 — Bus filter and three-scalar summing
- **Goal:** Sum exactly the internal + USB devices, and survive drives coming and going without tracking any of them. (FR-10, FR-10a–f, NFR-4)
- **Build:** Filter to `Physical Interconnect` ∈ {`Apple Fabric`, `PCI-Express`, `USB`}. Reduce each tick to **three scalars** — total bytes read, total bytes written, qualifying device count — and diff against the previous tick. Apply the FR-10e clamp: report 0 if either total decreased **or** the count changed. **Delete** `lastByName`, `activeInterfaces`, and `sourceText` from `SpeedSampler`; delete the caption from `ContentView`. No dictionary, no device identity, no classification cache (NFR-1 measured at 0.147 ms/tick — a cache would be complexity for no gain).
- **Verify:** Run a Finder copy from internal → USB and confirm read and write both rise (FR-5 §8 item 5), and that the total matches Activity Monitor's Disk tab. Then unplug a drive mid-transfer and confirm the app reports 0 for exactly **one** tick and recovers on the next — the accepted cost of FR-10e, and the thing to watch is that it is one tick, not a stuck or negative reading.
- **Done when:** Both buses contribute, the total matches Activity Monitor, and unplug costs exactly one sample. **Completes Phase 1.**

---

## Phase 2 — UI

### Increment 2.1 — Live numbers on screen
- **Goal:** Read/write figures render in the window. (FR-4, FR-17)
- **Build:** Rename `SpeedSample`'s `downMbps`/`upMbps` → `readMBps`/`writeMBps` through `SpeedHistory.swift`, `SpeedSampler.swift`, `SpeedReadout.swift`, `SpeedChart.swift`.
- **Verify:** Numbers update live and match the console.
- **Done when:** On-screen values track real disk activity.

### Increment 2.2 — Graph carried over
- **Goal:** The 60-second two-line graph plots read and write. (FR-7, FR-7a, FR-7b)
- **Build:** Mechanical — `SpeedChart` already takes `[SpeedSample]`. Axis unit label `Mbps` → `MB/s`; legend Download/Upload → Read/Write. **Keep the `Canvas` implementation** — do not regress to Charts (§6 of requirements).
- **Verify:** A `dd` burst draws a clear spike that scrolls left and falls off after 60 s.
- **Done when:** Both lines plot correctly with correct units.

### Increment 2.3 — Formatting, labels, units
- **Goal:** The readout matches FR-6 and doesn't jitter at real disk speeds. (FR-5, FR-6, NFR-3)
- **Build:** `ReadoutFormat.field` `intDigits` 3 → 4. In `SpeedReadout`, drop the `(Y.Y MBps)` parenthetical and the `/ 8.0` conversion entirely — one figure per row, `X.X MB/s`. Arrow icons and `SpeedPalette` unchanged.
- **Verify:** Drive the figure past 1,000 MB/s (internal SSD read, or internal + USB simultaneously) and confirm the layout holds steady without shifting.
- **Done when:** Readout is stable and correct from 0.0 through 4-digit values. **Completes Phase 2.**

---

## Phase 3 — Window behavior *(inherited)*

### Increment 3.1 — Verification pass
- **Goal:** Confirm NetSpeed's window behavior survived the re-badge. (FR-11, FR-12, FR-13, FR-14, FR-16)
- **Build:** None expected.
- **Verify:** Move and resize the window, quit, relaunch — position and size restore. Closing the window quits the app.
- **Done when:** All five FRs observed working. *(No code was changed here; this exists to catch a surprise from the bundle-ID change, which is what window restoration keys on.)*

---

## Phase 4 — Settings *(inherited)*

### Increment 4.1 — Verification pass
- **Goal:** Confirm the sampling-interval control still works. (FR-9, FR-9a–c)
- **Build:** None expected, beyond the help-string wording in `ContentView` ("network throughput" → "disk throughput").
- **Verify:** Change the interval; sampling cadence changes, the graph still spans 60 s, and the choice persists across a relaunch.
- **Done when:** All of FR-9 observed working.

---

## Phase 5 — Robustness and final check

### Increment 5.1 — Empty / zero state
- **Goal:** Sensible display when nothing is happening. (NFR-4)
- **Build:** Confirm idle renders `0.0 MB/s` and a flat baseline, not a degenerate axis. `SpeedChart.yGridValues` already falls back to `[0, 1]`.
- **Verify:** Let the machine idle; observe flat zero lines.
- **Done when:** Idle state is clean and stable.

### Increment 5.2 — Hot-plug and device-churn stress
- **Goal:** No crash, no false high reading, and no more than one dropped sample per event. (FR-10c–f, NFR-4)
- **Build:** None expected beyond 1.3.
- **Verify:** Unplug and re-plug USB drives several times while running, including during active I/O, and with two drives at once. The pass condition is asymmetric: a **0 for one tick is expected and acceptable** on any attach or detach (FR-10e); a **false high reading is not** and would indicate the count clamp is not firing. Also confirm the app is stable when *all* USB drives are removed, leaving only the internal SSD.
- **Done when:** Repeated churn produces no false highs, no crash, and no reading stuck at zero.

### Increment 5.3 — Footprint sanity check
- **Goal:** Confirm low CPU/memory in the assembled app. (NFR-1)
- **Build:** Profile a Release build.
- **Verify:** `sample` the Release build at 1 s sampling; CPU should sit near NetSpeed's post-5.2a footprint. The measurement pass itself is already known to cost 0.147 ms/tick (0.015% of a core), so anything materially above that is coming from the UI, not from IOKit — check `SpeedChart` first if so.
- **Done when:** Idle CPU is negligible and memory is flat over time.

### Increment 5.4 — Requirements traceability pass
- **Goal:** Every FR/NFR is met, deferred, or explicitly removed.
- **Build:** Walk the requirements doc top to bottom against the running app.
- **Verify:** Each requirement checked off with evidence.
- **Done when:** Full coverage confirmed → **v1.0**.

---

## Coverage map (requirement → increment)

| Requirement | Increment |
|---|---|
| FR-1, FR-2, FR-3 | Inherited (3.1) |
| FR-4 | 1.2, 2.1 |
| FR-5, FR-6 | 1.2, 2.3 |
| FR-7, FR-7a, FR-7b | 2.2 |
| FR-8 | 1.1, 1.2 |
| FR-9, FR-9a–c | 4.1 |
| FR-10, FR-10a, FR-10b | 1.3 |
| FR-10c – FR-10f | 1.3, 5.2 |
| FR-11 – FR-14, FR-16 | 3.1 |
| FR-17 | 2.1, 1.3 *(caption removal)* |
| FR-18 | 0.1 |
| NFR-1 | 5.3 *(pre-measured Aug 9: 0.147 ms/tick)* |
| NFR-2 | 1.1 *(pre-verified Aug 9)* |
| NFR-3 | 2.3 |
| NFR-4 | 5.1, 5.2 |
| NFR-5 | Inherited (palette + system styles) |

---

## Prerequisites before Increment 0.1

- [x] Requirements locked (`drive-speed-monitor-requirements.md` v1.0).
- [x] Counter source proven on the target machine, including under the App Sandbox.
- [x] Bus classification confirmed against real hardware (FR-10a).
- [ ] Chris approves this plan.
