# Drive Speed Monitor — Requirements

**Version:** 1.1
**Changelog:** v1.1 (Aug 10, 2026) — added **FR-6a**: figures below 1 MB/s auto-scale to **KB/s**, matching Activity Monitor, and the graph's y-axis scales with them. Chris's request, after noticing the divergence while cross-checking the two apps. v1.0 (Aug 9, 2026) — initial requirements, derived from NetSpeed v0.9.
**Date:** August 9, 2026 — last updated August 10, 2026
**Owner:** Chris
**Status:** **v1.0 shipped.** Every FR and NFR verified against the running app in the Increment 5.4 traceability pass (Aug 10, 2026). Derived from `network-speed-widget-requirements.md` v0.9 (NetSpeed v1.0, shipped Jul 13, 2026), which this project duplicates in structure and behavior. Every difference from that document is called out explicitly below.
**Lineage:** DriveSpeed is a near-exact duplicate of NetSpeed with one conceptual substitution — it measures **local disk throughput** instead of **network throughput**. Window behavior, layout, sampling control, and graph are carried over unchanged. Where an FR is unchanged from NetSpeed, it says so; where it changed, the change and its reason are recorded.

---

## 1. Overview

A lightweight macOS app that displays real-time local disk throughput (read and write) in a small floating desktop window. It measures actual I/O passively — it never generates its own disk load — and shows a short rolling graph so recent spikes and dips are visible at a glance.

This is a personal-use utility, built in Swift with Xcode. Sibling to NetSpeed.

## 2. Goals

- See current disk read/write speed at a glance without opening Activity Monitor.
- Zero added I/O — the tool observes, it does not benchmark.
- Stay out of the way: small, unobtrusive, remembers where I put it.

## 3. Non-Goals (v1)

- No benchmarking / max-throughput measurement (that is what a Blackmagic- or AJA-style tool is for; see also the sibling `USBDriveTester` project).
- No IOPS, latency, queue depth, per-process breakdown, or SMART health data.
- No long-term logging or historical storage to disk. *(Doubly important here — see FR-8.)*
- No menu bar presence, Notification Center widget, or multi-window support.
- No built-in launch-at-login; add DriveSpeed via System Settings → General → Login Items. *(Inherited from NetSpeed FR-15, removed there in v0.9.)*
- **No buses other than internal and USB.** Thunderbolt and SATA enclosures are deliberately out of scope — Chris has no such device on this Mac and could not test it. *(See FR-10 and §7.)*

## 4. Functional Requirements

### 4.1 Form factor
*Unchanged from NetSpeed FR-1 – FR-3.*
- FR-1: The app presents a single small **floating desktop window** the user can position anywhere on screen.
- FR-2: The window uses a **normal window level** (not forced always-on-top) in v1. *(Deferred — see §7.)*
- FR-3: The window is **opaque** in v1 (no adjustable transparency). *(Deferred — see §7.)*

### 4.2 What it measures and shows
- FR-4: Display **live read throughput** and **live write throughput**, updated each sample. *(Was download/upload.)*
- FR-5: Speeds are shown in **bytes per second only — never bits.** The primary unit is **MB/s (megabytes per second)**, bytes ÷ 1,000,000 on the decimal basis, consistent with §8 item 4; figures below 1 MB/s are shown in **KB/s** per FR-6a. **This is a change from NetSpeed's dual-unit FR-5** (which showed Mbps primary with MBps parenthetical). *(Reworded Aug 10, 2026 during the FR traceability pass — this read "MB/s only", which FR-6a contradicted the moment it was added. The intent was always "no megabits", not "no other byte unit".)* Storage is universally specified and discussed in MB/s — manufacturer sheets, enclosure ratings, and benchmark tools all use it — so the megabit figure carries no useful meaning here and only adds clutter. Chris's decision, Aug 9, 2026.
- FR-6: Each direction's readout shows one figure to **one decimal place** in the format **`X.X MB/s`** (e.g. `740.3 MB/s`), or `X.X KB/s` below the 1 MB/s boundary (FR-6a). Rendered with monospaced (tabular) digits in fixed-width fields so the readout doesn't shift as values change magnitude (NFR-3). **The fixed-width field is 4 integer digits** (up to `9999.9 MB/s` ≈ 10 GB/s), widened from NetSpeed's 3. Rationale: a single USB4 enclosure on this Mac was measured at **740 MB/s**, the M4's internal SSD runs to roughly 3,000 MB/s, and FR-10 sums both buses — so a 3-digit field would overflow routinely and defeat its own purpose.
- FR-6a: **Figures below 1 MB/s are shown in KB/s** — `847.3 KB/s` rather than `0.8 MB/s` — matching Activity Monitor, which the owner already reads alongside this app. *(Added v1.1, Aug 10, 2026, at Chris's request after noticing the divergence.)*
  - **1 KB = 1000 bytes**, not 1024, consistent with FR-5's decimal basis. Mixing a binary kilobyte into a decimal megabyte would make the two tiers disagree at the boundary.
  - **Each figure scales independently**, so the readout may legitimately show `847.3 KB/s` for reads beside `2.4 MB/s` for writes. That is what Activity Monitor does, and it beats forcing a shared unit and rendering one direction as `0.0`.
  - **The boundary belongs to MB/s:** exactly `1.0 MB/s` renders as MB/s; `0.9999` renders as `999.9 KB/s`.
  - **The fixed-width field survives the switch** (NFR-3): a KB/s figure is by definition under 1000 — 1000 KB/s *is* 1 MB/s — so both tiers fit the same four-digit field, and `MB/s` and `KB/s` are both four characters. The readout does not shift as a value crosses the boundary. Verified across the boundary in both directions.
- FR-7: Display a **rolling graph** (sparkline) of recent throughput, held **in memory only** — nothing is written to disk. *(Unchanged.)*
  - FR-7a: Graph window length: **60 seconds** of history. *(Unchanged.)*
  - FR-7b: Read and write are drawn as **two separate lines**, each a distinct color, with labels/units. *(Was download/upload.)*
  - FR-7c: The y-axis **shares the readout's unit rule** (FR-6a). Its unit is chosen from the largest value in the visible window — deliberately **not** from the rounded axis ceiling, because rounding can cross the 1 MB/s boundary: data peaking at 0.9 MB/s rounds to a ceiling of 1.0, which would label the axis in MB/s while the readout showed `900.0 KB/s`. With no data the axis keeps `MB/s` as a neutral placeholder rather than labelling its `[0, 1]` fallback ceiling `1000 KB/s`.

### 4.3 How it measures
- FR-8: Throughput is measured **passively** by reading the OS block-storage byte counters each interval and computing the delta over elapsed time. **The app generates no disk I/O of its own.** This constraint is stricter than NetSpeed's equivalent: a network monitor that logged to disk would not corrupt its own reading, but a *disk* monitor that did so would measure itself. FR-7's in-memory-only history is therefore load-bearing for measurement accuracy, not just a storage preference.
- FR-8a: **DriveSpeed measures device I/O, not application I/O — cached reads are invisible.** The block-storage counters increment only when bytes actually cross to or from the hardware. A file served from the unified page cache never reaches the device and therefore never appears in the reading, even though the application performed a full-speed read. This is correct behaviour for a *drive* speed monitor, but it has a visible consequence worth stating: re-reading a file you just wrote, or copying something recently touched, can show far less read activity than the transfer implies. Observed repeatedly during development — the same `dd` read measured 735 MB/s cold and 387 MB/s once the source was partly resident, and the internal SSD's shared-cache files read at only 402 MB/s across four parallel streams for the same reason. Do not treat the reading as a benchmark of what a drive *can* do (§3).
- FR-9: **Sampling interval is user-adjustable from 1 to 5 seconds.** *(Unchanged.)*
  - FR-9a: Default on first launch: **1 second.**
  - FR-9b: The chosen rate stays **fixed until the user changes it** (no auto-variation).
  - FR-9c: The rate is changed via an in-app control; the choice is remembered across launches.

### 4.4 Which storage interfaces
- FR-10: Measure throughput **summed across all physical storage devices on two buses — internal and USB** — so the reading reflects **total** disk activity regardless of which device carries it.
  - **Internal** — `Physical Interconnect` of `"Apple Fabric"` (Apple Silicon's ANS controller, how the M4 Mac mini's built-in SSD reports) **or** `"PCI-Express"`. Both map to the same bucket. *(Chris's shorthand for this bucket is "NVMe"; see the note below on why that string never appears.)*
  - **USB** — `Physical Interconnect` of `"USB"`. On this Mac this covers every external drive, including NVMe drives in USB enclosures.
  - **Everything else is excluded**, including Thunderbolt and SATA (§3).
- FR-10a: **"NVMe" is not a value macOS reports on this hardware, and this is not a naming quibble — it changes the filter.** Verified Aug 9, 2026 on the target machine (Mac mini M4, macOS 26.5.2): the internal 256 GB `APPLE SSD AP0256Z` (serial `0ba023036118a813`) reports `Apple Fabric`, and *every* external drive reports `USB` — including the 1 TB `Samsung SSD 990 EVO Plus`, which is physically an NVMe drive but sits in a USB enclosure. Note that only the internal SSD reports a serial through IOKit's `Device Characteristics`; the USB enclosures report none, so externals are identified here by capacity and product name. No device on this Mac reports `PCI-Express`. A filter written literally against `"NVMe"` or `"PCI-Express"` would therefore have measured **zero** on the internal side forever. `"PCI-Express"` is retained in the internal bucket only so the code stays correct on an Intel Mac or a genuine PCIe slot; it is not expected to match here.
- FR-10b: **Only the physical device layer is counted, so nothing is double-counted.** Matching on IOKit's `IOBlockStorageDriver` yields exactly one entry per physical whole disk — 5 on this Mac, matching `disk0/4/6/8/10`. APFS synthesized containers (`disk1/2/3/5/7/9`) have no `IOBlockStorageDriver` and are structurally invisible to the filter. Mounted disk images **do** get an `IOBlockStorageDriver`, but report `Physical Interconnect = "Virtual Interface"` and so fall outside the internal/USB filter — confirmed Aug 9, 2026 by attaching one and watching `readAll()` go from 5 devices to 6 while the sampled count held at 5. Their backing I/O is already counted once on the real device. A practical consequence worth stating: mounting or ejecting a sparsebundle, installer, or Time Machine image causes **no** FR-10e clamp — an excluded device never contributes to the totals, so neither attaching nor detaching one can move them. *(Reworded Aug 10, 2026: this previously reasoned via "the sampled device count never changes", a count that FR-10e-i removed. The conclusion is unchanged; only the justification needed repair.)* This is the disk analogue of NetSpeed's FR-10 exclusion of VPN/virtual interfaces, but it requires no explicit exclusion list — the layer choice does the work.
- FR-10c: **Counters are per-attachment, not lifetime — verified Aug 9, 2026.** A freshly attached block device's `IOBlockStorageDriver` is instantiated at attach time with its `Statistics` starting at zero; it does **not** carry the drive's accumulated history. Measured directly: a newly attached device read `Bytes (Read)` = 194,560 and `Bytes (Write)` = 8,704 — just the mount's own probe I/O from the preceding second. Two consequences follow, and they are the opposite of what one might assume:
  - **Attaching a drive cannot produce a false spike.** A new device joins the total at ~0, so even a naive sum-of-all-devices would see a negligible bump. *(An earlier draft of this document claimed a multi-gigabyte attach spike. That was wrong — it assumed lifetime counters and was not tested.)*
  - **Detaching a drive removes its accumulated bytes from the total.** A drive that has read 35 GB since attach drops the running total by 35 GB when unplugged, producing a large negative delta for that one tick.
- FR-10d: **No per-device identity is tracked.** Each tick reduces the qualifying devices to **two scalars** — total bytes read and total bytes written — and diffs those against the previous tick. There is no per-device dictionary, no registry entry ID, and no BSD-name keying, so BSD-name recycling is a non-issue *by construction* rather than by mitigation. The BSD name and product name are not read at all in the shipped app. *(Chris's decision, Aug 9, 2026: the alternative — per-device deltas — was only required to drive an "active drives" caption, which was dropped. See §7.)* *(Corrected Aug 10, 2026 during the FR traceability pass: this said "three scalars" including a device count, which FR-10e-i had already removed. Anyone implementing from the stale text would have rebuilt the discarded clamp.)*
- FR-10e: **Decrease guard.** A tick reports **0** for *both* figures if either total decreased since the previous tick — which means a device left the sampled set and took its accumulated bytes with it (FR-10c's detach case). Both are clamped together because if a drive departed mid-interval, neither number describes a real interval.

  This is **not a policy choice**: `current - previous` on `UInt64` underflows to an astronomical value, so the guard prevents garbage rather than merely an unwanted reading. Accepted cost: one dropped sample whenever a drive with accumulated bytes is unplugged.
- FR-10e-i: **No device-count check.** *(Built in Increment 1.3, removed immediately after on Chris's call, Aug 10, 2026.)* A `deviceCount` field on the totals, clamping whenever the sampled device set changed, was intended to close the one path by which a scalar design could report a false **high** reading — a device transiently failing classification and rejoining on a later tick with its accumulated counter intact. It was removed because the trade does not hold up:
  - **Attaching cannot spike.** Counters start near zero on attach (FR-10c, measured), so a joining device contributes ~0 regardless.
  - **Detaching already trips the decrease guard**, with or without a count check.
  - So the count check's *only* unique benefit was the speculative misclassification case, never observed — while its cost was discarding a valid reading on **every** attach.
  - **DriveSpeed is a monitoring tool, not a benchmark** (Chris, Aug 9, 2026). A transient false reading is acceptable: a spike leaves the 60-second ring buffer on its own and the auto-scaled y-axis recovers. The earlier "a false spike would flatten a minute of real data" argument overstated the harm — it is bounded at 60 seconds and self-healing.
- FR-10f: **The baseline is primed at `start()`, not on the first tick.** `start(intervalSeconds:)` reads the totals and timestamps them *before* arming the timer, so the first tick is a real delta over one interval rather than a spike measured from zero. This is also why changing the sampling rate mid-run produces no artefact — `setInterval` re-enters `start()`, which re-primes. The tick still guards defensively: with no baseline, or a non-positive elapsed interval, it primes and waits rather than dividing by zero (NFR-4). *(Corrected Aug 9, 2026 — an earlier draft of this document said the first tick reports 0, which would have been true only if the baseline were primed lazily. NetSpeed primed eagerly and so does this.)*

### 4.5 Window behavior
*Unchanged from NetSpeed FR-11 – FR-16.*
- FR-11: **Remember window position** across launches and restarts.
- FR-12: **Remember window size** across launches and restarts.
- FR-13: On the **very first launch**, the window appears in the **top-left** of the screen. Note: because the bundle identifier changes (§6), DriveSpeed has no saved frame inherited from NetSpeed and will genuinely exercise this path on first run.
- FR-14: **Default window size is medium** (sized to show the numbers plus a legible 60-second two-line graph) and the window is **resizable**.
- FR-15: *(Removed, inherited from NetSpeed v0.9.)* Launch at login is not managed by the app.
- FR-16: **Closing the window quits the app.** There is no menu bar item in v1; to reopen, relaunch.

### 4.6 Layout
- FR-17: Content layout is **numbers on top, graph below**, with the numeric readout **horizontally centered** and staying centered as the window resizes. *(Unchanged.)* The bottom row now holds **only the sampling-interval control**, right-aligned — NetSpeed shared that row with its active-interface caption, which is dropped here (FR-10d).
- FR-18: The main window uses the **standard native title bar**, titled with the app name followed by its **major.minor version** — e.g. **"DriveSpeed 1.0"** — read from the bundle's marketing version (`CFBundleShortVersionString`). *(Unchanged mechanism; app name differs.)*

## 5. Non-Functional Requirements

- NFR-1: **Low footprint** — **measured Aug 9, 2026, and it is a non-issue.** A full tick (enumerate every `IOBlockStorageDriver`, walk each one's parent chain to classify its bus, read and sum the statistics) costs **0.147 ms** — mean over 200 passes on the target machine, 5 qualifying devices. At 1 Hz that is **0.015% of one core**. For scale, the SwiftUI Charts render that NetSpeed removed in its Increment 5.2a cost ~24 ms per tick, roughly **163× more** than this entire measurement pass. An earlier draft proposed caching bus classification per device to avoid the parent-chain search; the measurement makes that pure complexity for no gain, so **there is no cache** — classification is recomputed every tick.

  **Confirmed on the assembled Release build (Aug 10, 2026, Increment 5.3):** 464 KB bundle; **0.4% average CPU**; a 5-second `sample` put **99.3% of main-thread samples idle in `mach_msg`**, with `SpeedChart.draw` at ~0.1% and `SpeedSampler.tick` at ~0.1%. Memory rose 91.6 → 94.0 MB during the first ~40 s — the ring buffer filling — then drifted **48 KB across the next three minutes**, i.e. flat.
- NFR-2: **No elevated privileges** — **verified Aug 9, 2026.** The counter read was exercised from a signed `.app` carrying `com.apple.security.app-sandbox` and returned full statistics for all five devices with **no entitlement exceptions** and no `IOServiceGetMatchingServices` failure. The existing target's `ENABLE_APP_SANDBOX = YES` can stay on.
- NFR-3: **Readable at a glance** — clear numbers, legible at the default medium size and when resized smaller.
- NFR-4: **Resilient** — if no qualifying device is present, all devices are idle, or counters are briefly unavailable, show a sensible zero state rather than crashing. Covers hot-plug (FR-10c, FR-10d).
- NFR-5: **Respects system appearance** — the UI follows the system **light/dark** setting.

## 6. Technical Notes

- **Language / UI:** Swift + SwiftUI throughout — no AppKit/`NSWindow` hosting. *(Unchanged; proven in NetSpeed.)*
- **Project identity:** product name `DriveSpeed`; organization identifier `com.arc3solutions`; bundle identifier `com.arc3solutions.DriveSpeed`.
- **Minimum OS:** **macOS 26 Tahoe** or later. **Architecture:** Apple Silicon (`arm64`) only. *(Unchanged.)*
- **Throughput source:** IOKit. Match `IOServiceMatching("IOBlockStorageDriver")`, then read the `Statistics` property (`kIOBlockStorageDriverStatisticsKey`) and take `kIOBlockStorageDriverStatisticsBytesReadKey` / `kIOBlockStorageDriverStatisticsBytesWrittenKey`. Throughput = byte delta ÷ elapsed time. Requires `import IOKit` and `import IOKit.storage`. No special entitlements (NFR-2).
- **Counters are 64-bit.** This is a real simplification over NetSpeed: `getifaddrs`'s `if_data` counters are 32-bit and wrap at 4 GiB, which NetSpeed had to guard against explicitly and which was observed happening in practice. The block-storage counters are 64-bit (the internal SSD already reads ~246 GB cumulative), so wrap is not a practical concern. The `now < last` guard is nonetheless **retained** — it costs nothing and still correctly handles a counter reset on device re-enumeration.
- **Bus classification:** `IORegistryEntrySearchCFProperty` with `kIORegistryIterateParents | kIORegistryIterateRecursively` for `"Protocol Characteristics"`, then read `"Physical Interconnect"`. That single property is the whole filter. `"Physical Interconnect Location"`, `"Device Characteristics"` → `"Product Name"`, and the BSD name are **not read** — they existed only for the Phase 1 console snapshot, and were removed along with it in Increment 2.3 (FR-10d). Dropping them also removed two registry searches per device per tick. *(Updated Aug 10, 2026 — this previously said they "should not survive into the shipped sampler", written while they still did.)*
- **Device identity:** none. See FR-10d.
- **Swift bridging gotcha (recorded so it isn't re-derived):** `IORegistryEntrySearchCFProperty` returns an **already-retained `CFTypeRef?`** in Swift and must be cast directly (`... as? [String: Any]`), whereas `IORegistryEntryCreateCFProperty` returns `Unmanaged<CFTypeRef>!` and needs `.takeRetainedValue()`. Mixing them up is a compile error, hit during the Aug 9 prototype.
- **Remember position & size:** the SwiftUI `Window` scene persists its frame with no explicit persistence code. **Observed Aug 10, 2026, and it is not what the inherited NetSpeed note described:** the frame lives in the app's own `UserDefaults` as a `NSWindow Frame main` key — keyed off the scene's `id: "main"` — e.g. `"1136 148 1313 747 0 0 2560 1410"`. There is **no** `~/Library/Saved Application State/com.arc3solutions.DriveSpeed.savedState` directory at all. NetSpeed's §6 described this as system window restoration "honoring the *Close windows when quitting an application* setting"; a `UserDefaults` frame autosave would not depend on that setting, which if anything makes persistence more robust than documented. Recorded as an **observation, not a guarantee** — the mechanism is the framework's choice, not ours, and the requirement is only that the frame is remembered.
- **FR-16 needs no code.** Closing the window quits the app by macOS 26 SwiftUI default for a single unique `Window` scene — inherited from NetSpeed's Increment 3.4, which confirmed by inspection that nothing in the project forces it (no `Info.plist`, no `LSUIElement`, no `@NSApplicationDelegateAdaptor`, no `applicationShouldTerminateAfterLastWindowClosed`). Re-confirmed for DriveSpeed by the same inspection. NetSpeed also settled the follow-on question: frame restoration survives the **close→quit** path, not only ⌘Q.
- **Rolling graph:** in-memory ring buffer of the last 60 s, rendered with SwiftUI **`Canvas`** — not Charts. NetSpeed migrated to `Canvas` in its Increment 5.2a after profiling showed each 1 Hz Charts re-render costing ~24 ms of main-thread work (~97% of app CPU). DriveSpeed inherits the `Canvas` implementation directly and must not regress to Charts.
- **Sampling control:** timer bound to a user setting (1–5 s), persisted in `UserDefaults` via `@AppStorage`. *(Unchanged.)*

## 7. Deferred / Future Considerations

- Always-on-top window level; adjustable window transparency. *(Inherited.)*
- **Thunderbolt and SATA buses** — excluded from v1 for lack of testable hardware (§3). The FR-10 filter is a small allowlist, so adding a bus is a one-line change if a device ever arrives.
- **An "active drives" caption** naming which drives are currently busy — NetSpeed's `sourceText` equivalent. **Dropped Aug 9, 2026** (Chris's decision). Reinstating it means reinstating per-device deltas and therefore device identity (FR-10d), so it is the one deferred item with a real structural cost rather than a purely additive one.
- Per-device breakdown (a row per drive rather than a summed pair) — same dependency as above.
- Splitting the readout by bus (e.g. "Internal 500 / USB 240") rather than one summed figure. Cheaper than the two items above: it needs two scalar pairs, not device identity.
- IOPS, latency, and queue-depth metrics.
- Auto-adaptive sampling; persistent logging; longer history windows.
- A menu bar item.

## 8. Decisions Made Without a Direct Question (please veto if any are wrong)

1. **Product name is `DriveSpeed`** (bundle `com.arc3solutions.DriveSpeed`), paralleling `NetSpeed` as the folder name `drive-speed-monitor` parallels `network-speed-monitor`.
2. **Direction labels are "Read" and "Write"** — not "In/Out" or "Down/Up".
3. **Read is blue, write is red**, inheriting NetSpeed's `SpeedPalette` unchanged: read is data in, write is data out, so the existing mapping carries over without redefinition.
4. **MB/s uses the decimal 1,000,000 basis**, not 1,048,576 — consistent with NetSpeed's FR-5 basis and with how drive and enclosure speeds are advertised.
5. **Read and write can both be high simultaneously and that is correct, not double-counting.** Copying a file from the internal SSD to a USB drive genuinely reads ~N MB/s and writes ~N MB/s across the two buses; the read/write split represents this accurately.
6. **The 60-second window and 1–5 s interval range carry over unchanged.** Disk I/O is burstier than network traffic, but no evidence yet suggests the existing range is wrong. Revisit only if it proves unreadable in practice.

## 9. Assumptions

- Single user, single machine, personal use.
- The rolling graph is transient; quitting the app discards history by design.
- The target machine is the Mac mini M4 described in FR-10a. Bus classification on other Macs is handled defensively but is untested.

---

*Next step: `drive-speed-monitor-build-plan.md` breaks this into small, verifiable increments.*
