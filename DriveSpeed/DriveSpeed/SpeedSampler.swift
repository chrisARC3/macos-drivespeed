//
//  SpeedSampler.swift
//  DriveSpeed
//
//  Polls block-storage byte counters on a timer and publishes live read/write
//  throughput, summed across physical storage devices. Increment 1.2 — the
//  IOKit counter source, scalar totals, and MB/s math (replaces NetSpeed's
//  getifaddrs/per-interface version).
//

import Foundation
import Observation

/// Scalar byte totals across the sampled devices for a single tick.
///
/// The whole of the sampler's per-tick state, by design: per FR-10d DriveSpeed
/// tracks **no device identity at all** — no dictionary, no registry entry IDs,
/// no BSD names. Increment 1.3 adds a device count to this struct to support the
/// FR-10e clamp.
/// `nonisolated` because the target sets `SWIFT_DEFAULT_ACTOR_ISOLATION =
/// MainActor` — see the note on `DriveCounter`. This type is produced by the
/// off-actor sampling helper, so it must not inherit main-actor isolation.
nonisolated struct DriveTotals {
    var bytesRead: UInt64 = 0
    var bytesWritten: UInt64 = 0
}

/// Polls the OS block-storage byte counters on a fixed interval, sums the
/// per-interval byte deltas across physical storage devices, and publishes the
/// result for the UI to display. Console output is retained for debugging
/// through Phase 1.
///
/// **Scope caveat (Increment 1.2):** this currently sums *every* physical device
/// `DriveCounters.readAll()` reports. Increment 1.3 narrows it to the FR-10
/// internal + USB buses and adds the FR-10e clamp. On the development machine
/// every attached device is already internal or USB, so today's numbers happen
/// to agree with the eventual filtered ones — but they are not FR-10-correct
/// until 1.3, and a Thunderbolt or SATA device would silently be included.
///
/// Counter behaviour, which differs from NetSpeed's in two ways that matter:
/// the block-storage counters are **64-bit**, so the 4 GiB wrap NetSpeed had to
/// guard against cannot happen; and they are **per-attachment**, so a device
/// joining mid-run starts near zero and cannot inject a false spike (FR-10c).
/// The `now < last` guard is kept anyway — it is free, and it is what catches
/// the *detach* case, where a departing device's accumulated bytes leave the
/// total and drive the delta negative.
@Observable
@MainActor
final class SpeedSampler {

    // MARK: Published throughput (read by the SwiftUI view)

    /// Live read throughput, summed over the sampled devices, in MB/s (FR-5).
    private(set) var readMBps: Double = 0
    /// Live write throughput, summed over the sampled devices, in MB/s (FR-5).
    private(set) var writeMBps: Double = 0

    /// Rolling in-memory history for the 60-second graph (FR-7), oldest→newest.
    /// Capacity tracks the sampling interval as `60 / interval + 1` so the buffer
    /// always spans a full FR-7a 60-second window: 61 points at 1 s down to 13 at
    /// 5 s, via `historyCapacity(forIntervalSeconds:)`. The `+1` is the fencepost —
    /// spanning 60 s takes one point at each step from −60 s to 0 s; with only
    /// `60 / interval` the oldest sample would sit one tick inside the chart's
    /// fixed [−60 s, now] domain and the line would stop short of the left "60s"
    /// axis. `start(intervalSeconds:)` sizes it; the 61 here is just the 1 s
    /// default until then.
    private(set) var history = RingBuffer<SpeedSample>(capacity: 61)

    // MARK: Internal bookkeeping (not observed)

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTotals: DriveTotals?
    @ObservationIgnored private var lastTime: Date?

    /// Current sampling interval in whole seconds (FR-9, 1–5 s; default 1 s per
    /// FR-9a). Drives both the timer cadence and the history buffer's capacity;
    /// `start(intervalSeconds:)` and `setInterval(seconds:)` keep it in sync.
    @ObservationIgnored private var intervalSeconds: Int = 1

    // MARK: Lifecycle

    /// Begins sampling every `intervalSeconds` seconds (FR-9, 1–5 s; default 1 s
    /// per FR-9a). Safe to call repeatedly — `setInterval(seconds:)` reuses it to
    /// re-arm at a new rate: each call re-primes the baseline so the first sample
    /// is a real delta rather than a spike measured from zero (FR-10f), and
    /// rebuilds the history buffer to the capacity that keeps the graph a full
    /// 60-second window at this interval (so changing the rate restarts the
    /// graph — FR-7).
    func start(intervalSeconds: Int = 1) {
        stop()

        self.intervalSeconds = intervalSeconds
        history = RingBuffer<SpeedSample>(capacity: Self.historyCapacity(forIntervalSeconds: intervalSeconds))
        lastTotals = Self.currentTotals()
        lastTime = Date()

        let period = TimeInterval(intervalSeconds)
        let t = Timer.scheduledTimer(withTimeInterval: period, repeats: true) { [weak self] _ in
            // The timer is scheduled on — and fires on — the main run loop
            // (SpeedSampler is @MainActor, so start() runs there), so we are
            // already on the main actor here. Assert it to satisfy the compiler
            // without an extra async hop.
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        t.tolerance = period * 0.1
        timer = t
    }

    /// Changes the sampling interval live (FR-9c). While sampling, re-arms the
    /// timer at the new rate via `start(intervalSeconds:)` — which also re-primes
    /// the baseline and resizes the graph to hold its 60-second window. A no-op if
    /// the rate is unchanged; if not currently sampling, the value is stored and
    /// takes effect at the next `start`.
    func setInterval(seconds: Int) {
        guard seconds != intervalSeconds else { return }
        if timer != nil {
            start(intervalSeconds: seconds)
        } else {
            intervalSeconds = seconds
        }
    }

    /// History capacity that keeps the graph a full 60-second window at a given
    /// interval: `60 / interval + 1` (the `+1` is the fencepost — see `history`).
    /// 1 s → 61, 2 s → 31, 3 s → 21, 4 s → 16, 5 s → 13. `nonisolated` so it stays
    /// a pure function callable off the main actor (and headless-testable).
    nonisolated static func historyCapacity(forIntervalSeconds seconds: Int) -> Int {
        60 / max(1, seconds) + 1
    }

    /// Stops sampling.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Sampling

    private func tick() {
        let now = Date()
        let current = Self.currentTotals()

        let elapsed = now.timeIntervalSince(lastTime ?? now)
        guard elapsed > 0, let previous = lastTotals else {
            // No usable baseline yet (or a zero-length interval): prime and wait
            // for the next tick rather than dividing by zero (NFR-4).
            lastTotals = current
            lastTime = now
            return
        }

        let read = Self.rate(from: previous.bytesRead, to: current.bytesRead, over: elapsed)
        let write = Self.rate(from: previous.bytesWritten, to: current.bytesWritten, over: elapsed)

        readMBps = read
        writeMBps = write
        history.append(SpeedSample(time: now, readMBps: read, writeMBps: write))

        // Increment 1.2 scaffolding — removed in the Phase 2 cleanup, once the
        // numbers are on screen, exactly as NetSpeed's console output was.
        print(String(format: "R %8.2f MB/s   W %8.2f MB/s", read, write))

        lastTotals = current
        lastTime = now
    }

    /// MB/s between two cumulative byte readings (FR-5: bytes ÷ 1,000,000, the
    /// decimal basis). A counter that went *down* means devices left the sampled
    /// set — their accumulated bytes went with them — so the interval is reported
    /// as 0 rather than underflowing `UInt64` (FR-10c). `nonisolated` and pure so
    /// it can be unit-tested headlessly.
    nonisolated static func rate(from previous: UInt64, to current: UInt64, over elapsed: TimeInterval) -> Double {
        guard elapsed > 0, current >= previous else { return 0 }
        return Double(current - previous) / elapsed / 1_000_000
    }

    /// Summed cumulative byte counters across the sampled physical devices.
    ///
    /// Increment 1.3 adds the FR-10 bus filter (internal + USB) and a device
    /// count here; today it sums everything `DriveCounters` reports.
    nonisolated static func currentTotals() -> DriveTotals {
        var totals = DriveTotals()
        for drive in DriveCounters.readAll() {
            totals.bytesRead &+= drive.bytesRead
            totals.bytesWritten &+= drive.bytesWritten
        }
        return totals
    }
}
