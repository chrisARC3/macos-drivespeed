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
/// no BSD names. Two integers are the entire memory of the previous tick.
///
/// An earlier cut carried a `deviceCount` so the clamp could also fire when the
/// device set changed. It was removed (FR-10e-i): attaching a drive cannot spike,
/// because counters start near zero on attach, and detaching already trips the
/// decrease guard — so the count check's only unique benefit was a speculative
/// misclassification case, paid for by discarding a valid reading on every
/// attach. DriveSpeed is a monitoring tool, and a transient anomaly leaves the
/// 60-second window on its own.
///
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
/// Device scope is the FR-10 filter: internal storage (`Apple Fabric` on Apple
/// Silicon, or `PCI-Express`) plus `USB`, summed into a single pair of figures.
/// Thunderbolt, SATA, and anything unrecognised are excluded (§3).
///
/// Counter behaviour, which differs from NetSpeed's in two ways that matter:
/// the block-storage counters are **64-bit**, so the 4 GiB wrap NetSpeed had to
/// guard against cannot happen; and they are **per-attachment**, so a device
/// joining mid-run starts near zero and cannot inject a false spike (FR-10c).
/// Attaching is therefore the harmless case; *detaching* is the one that needs
/// handling, because a departing device's accumulated bytes leave the total and
/// drive the delta negative.
///
/// Hence the guard in `rates(from:to:over:)`: a tick reports 0 if either total
/// decreased. That is not a policy choice — `current - previous` on `UInt64`
/// would underflow to an astronomical value, so the guard prevents garbage
/// rather than merely an unwanted reading. It costs one dropped sample when a
/// drive with accumulated bytes is unplugged, which is accepted (FR-10e).
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

        // A nil result is the FR-10e guard firing: a total went backwards, so a
        // device left the sampled set and this interval is not measurable.
        let measured = Self.rates(from: previous, to: current, over: elapsed)
        let read = measured?.read ?? 0
        let write = measured?.write ?? 0

        readMBps = read
        writeMBps = write
        history.append(SpeedSample(time: now, readMBps: read, writeMBps: write))

        // Phase 1 scaffolding — removed in the Increment 2.3 cleanup, once the
        // numbers are on screen, exactly as NetSpeed's console output was.
        print(String(format: "R %8.2f MB/s   W %8.2f MB/s%@", read, write,
                     measured == nil ? "   — counter decreased (drive removed)" : ""))

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

    /// Read/write MB/s between two consecutive totals, or `nil` when the interval
    /// is not measurable and must be reported as 0 — the FR-10e clamp.
    ///
    /// Returning an optional rather than a zeroed pair is deliberate: the caller
    /// needs to distinguish "genuinely idle" from "unmeasurable", and making that
    /// distinction part of the type keeps the clamp logic in exactly one place.
    ///
    /// The interval is unmeasurable when **either total decreased**, which means
    /// a device left the sampled set and took its accumulated bytes with it.
    ///
    /// Both figures are clamped together, not just the one that moved: if a drive
    /// departed mid-interval, neither number describes a real interval. That is
    /// the one behaviour this function adds over calling `rate` twice, which
    /// would zero only the figure that went backwards.
    nonisolated static func rates(from previous: DriveTotals,
                                  to current: DriveTotals,
                                  over elapsed: TimeInterval) -> (read: Double, write: Double)? {
        guard elapsed > 0,
              current.bytesRead >= previous.bytesRead,
              current.bytesWritten >= previous.bytesWritten
        else { return nil }

        return (rate(from: previous.bytesRead, to: current.bytesRead, over: elapsed),
                rate(from: previous.bytesWritten, to: current.bytesWritten, over: elapsed))
    }

    /// Summed cumulative byte counters across the physical devices on the buses
    /// DriveSpeed samples (FR-10 — internal plus USB).
    ///
    /// No cache: `DriveCounters.isSampled` is re-evaluated per device per tick.
    /// A full pass costs 0.147 ms — about 0.015% of one core at 1 Hz — so caching
    /// classification against device identity would be complexity for no gain,
    /// and would reintroduce exactly the per-device bookkeeping FR-10d removes.
    nonisolated static func currentTotals() -> DriveTotals {
        var totals = DriveTotals()
        for drive in DriveCounters.readAll() where DriveCounters.isSampled(interconnect: drive.interconnect) {
            totals.bytesRead &+= drive.bytesRead
            totals.bytesWritten &+= drive.bytesWritten
        }
        return totals
    }
}
