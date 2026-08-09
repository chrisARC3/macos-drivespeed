# Drive Speed Monitor — Requirements

**Version:** 1.0
**Date:** August 9, 2026
**Owner:** Chris
**Status:** Requirements complete. Derived from `network-speed-widget-requirements.md` v0.9 (NetSpeed v1.0, shipped Jul 13, 2026), which this project duplicates in structure and behavior. Every difference from that document is called out explicitly below.
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
- FR-5: Speeds are shown in **MB/s (megabytes per second)** only — bytes ÷ 1,000,000, the decimal basis, consistent with §8 item 4. **This is a change from NetSpeed's dual-unit FR-5** (which showed Mbps primary with MBps parenthetical). Storage is universally specified and discussed in MB/s — manufacturer sheets, enclosure ratings, and benchmark tools all use it — so the megabit figure carries no useful meaning here and only adds clutter. Chris's decision, Aug 9, 2026.
- FR-6: Each direction's readout shows one figure to **one decimal place** in the format **`X.X MB/s`** (e.g. `740.3 MB/s`). Rendered with monospaced (tabular) digits in fixed-width fields so the readout doesn't shift as values change magnitude (NFR-3). **The fixed-width field is 4 integer digits** (up to `9999.9 MB/s` ≈ 10 GB/s), widened from NetSpeed's 3. Rationale: a single USB4 enclosure on this Mac was measured at **740 MB/s**, the M4's internal SSD runs to roughly 3,000 MB/s, and FR-10 sums both buses — so a 3-digit field would overflow routinely and defeat its own purpose.
- FR-7: Display a **rolling graph** (sparkline) of recent throughput, held **in memory only** — nothing is written to disk. *(Unchanged.)*
  - FR-7a: Graph window length: **60 seconds** of history. *(Unchanged.)*
  - FR-7b: Read and write are drawn as **two separate lines**, each a distinct color, with labels/units. *(Was download/upload.)*

### 4.3 How it measures
- FR-8: Throughput is measured **passively** by reading the OS block-storage byte counters each interval and computing the delta over elapsed time. **The app generates no disk I/O of its own.** This constraint is stricter than NetSpeed's equivalent: a network monitor that logged to disk would not corrupt its own reading, but a *disk* monitor that did so would measure itself. FR-7's in-memory-only history is therefore load-bearing for measurement accuracy, not just a storage preference.
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
- FR-10b: **Only the physical device layer is counted, so nothing is double-counted.** Matching on IOKit's `IOBlockStorageDriver` yields exactly one entry per physical whole disk — 5 on this Mac, matching `disk0/4/6/8/10`. APFS synthesized containers (`disk1/2/3/5/7/9`) have no `IOBlockStorageDriver` and are structurally invisible to the filter. Mounted disk images likewise fall outside the internal/USB bus filter, and their backing I/O is already counted once on the real device. This is the disk analogue of NetSpeed's FR-10 exclusion of VPN/virtual interfaces, but it requires no explicit exclusion list — the layer choice does the work.
- FR-10c: **Counters are per-attachment, not lifetime — verified Aug 9, 2026.** A freshly attached block device's `IOBlockStorageDriver` is instantiated at attach time with its `Statistics` starting at zero; it does **not** carry the drive's accumulated history. Measured directly: a newly attached device read `Bytes (Read)` = 194,560 and `Bytes (Write)` = 8,704 — just the mount's own probe I/O from the preceding second. Two consequences follow, and they are the opposite of what one might assume:
  - **Attaching a drive cannot produce a false spike.** A new device joins the total at ~0, so even a naive sum-of-all-devices would see a negligible bump. *(An earlier draft of this document claimed a multi-gigabyte attach spike. That was wrong — it assumed lifetime counters and was not tested.)*
  - **Detaching a drive removes its accumulated bytes from the total.** A drive that has read 35 GB since attach drops the running total by 35 GB when unplugged, producing a large negative delta for that one tick.
- FR-10d: **No per-device identity is tracked.** Each tick reduces the qualifying devices to **three scalars** — total bytes read, total bytes written, and the number of devices that contributed — and diffs those against the previous tick. There is no per-device dictionary, no registry entry ID, and no BSD-name keying, so BSD-name recycling is a non-issue *by construction* rather than by mitigation. The BSD name and product name are not read at all in the shipped app. *(Chris's decision, Aug 9, 2026: the alternative — per-device deltas — was only required to drive an "active drives" caption, which was dropped. See §7.)*
- FR-10e: **Clamp rule.** A tick reports **0** if either total decreased **or** the qualifying-device count changed since the previous tick. Two cases motivate this:
  - *Decrease* is FR-10c's detach case. Accepted cost: **one dropped sample** whenever a drive with accumulated bytes is unplugged. This is the deliberate trade for dropping the caption.
  - *Count change* covers a device transiently failing classification and returning on a later tick carrying accumulated bytes — the one path by which a scalar design could otherwise report a false **high** reading. Clamping on any count change closes it for the cost of one sample per attach or detach, both rare.
  - Residual, accepted: two devices leaving and joining within the same tick would leave the count unchanged. Vanishingly unlikely, and a simultaneous detach would almost certainly drive the total negative and clamp anyway.
- FR-10f: On the **first tick after start** there is no previous sample, so the tick reports 0 and primes the baseline (NFR-4). Unchanged in spirit from NetSpeed.

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
- **Bus classification:** `IORegistryEntrySearchCFProperty` with `kIORegistryIterateParents | kIORegistryIterateRecursively` for `"Protocol Characteristics"`, then read `"Physical Interconnect"`. That single property is the whole filter. `"Physical Interconnect Location"`, `"Device Characteristics"` → `"Product Name"`, and the BSD name are **not read** — they existed only to label the dropped caption (FR-10d). They remain useful for `print()` debugging during Phase 1 and should not survive into the shipped sampler.
- **Device identity:** none. See FR-10d.
- **Swift bridging gotcha (recorded so it isn't re-derived):** `IORegistryEntrySearchCFProperty` returns an **already-retained `CFTypeRef?`** in Swift and must be cast directly (`... as? [String: Any]`), whereas `IORegistryEntryCreateCFProperty` returns `Unmanaged<CFTypeRef>!` and needs `.takeRetainedValue()`. Mixing them up is a compile error, hit during the Aug 9 prototype.
- **Remember position & size:** macOS automatic window restoration for the SwiftUI `Window` scene. *(Unchanged.)*
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
