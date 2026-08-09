//
//  SpeedSampler.swift
//  DriveSpeed
//
//  Polls interface byte counters on a timer and publishes live download/upload
//  throughput, summed across all physical (en*) interfaces. Increments 1.2
//  (timer + Mbps/MBps), 2.1 (publish to the UI via @Observable), and the v0.4
//  FR-10 change (sum all physical interfaces instead of a single primary).
//

import Foundation
import Observation

/// Polls the OS interface byte counters on a fixed interval, sums the
/// per-interval byte deltas across all physical network interfaces (BSD `en*`
/// — Ethernet, Wi-Fi, wired adapters), and publishes the result for the UI to
/// display. Console output is retained for debugging during Phase 2.
///
/// Interface scope (FR-10, requirements v0.4): we sum every `en*` interface so
/// the reading reflects *total* network throughput regardless of which interface
/// carries it — matching Activity Monitor. This catches several interfaces being
/// active at once (e.g. an SMB mount bound to Wi-Fi while the internet default
/// route is on Ethernet). Loopback and virtual interfaces (VPN `utun*`, AirDrop
/// `awdl*`/`llw*`, bridges) are excluded: VPN traffic is already counted once on
/// the physical interface it rides, so including the tunnel too would double-count.
///
/// Counter wrap: `getifaddrs` exposes 32-bit byte counters that wrap at 4 GiB.
/// A wrap — or an interface counter reset — shows up as `now < last`; we treat
/// that interval as 0 for that interface rather than underflowing `UInt64`.
@Observable
@MainActor
final class SpeedSampler {

    // MARK: Published throughput (read by the SwiftUI view)

    /// Live download throughput, summed over physical interfaces, in Mbps.
    private(set) var downMbps: Double = 0
    /// Live upload throughput, summed over physical interfaces, in Mbps.
    private(set) var upMbps: Double = 0
    /// Names of the physical interfaces that carried traffic this tick.
    private(set) var activeInterfaces: [String] = []

    /// Rolling in-memory history for the 60-second graph (FR-7), oldest→newest.
    /// Capacity tracks the sampling interval as `60 / interval + 1` so the buffer
    /// always spans a full FR-7a 60-second window: 61 points at 1 s down to 13 at
    /// 5 s (Increment 4.1, via `historyCapacity(forIntervalSeconds:)`). The `+1` is
    /// the fencepost — spanning 60 s takes one point at each step from −60 s to 0 s;
    /// with only `60 / interval` the oldest sample would sit one tick inside the
    /// chart's fixed [−60 s, now] domain and the line would stop short of the left
    /// "60s" axis (the off-by-one fixed in 2.2). `start(intervalSeconds:)` sizes it;
    /// the 61 here is just the 1 s default until then.
    private(set) var history = RingBuffer<SpeedSample>(capacity: 61)

    /// Caption describing where the traffic is currently coming from.
    var sourceText: String {
        activeInterfaces.isEmpty
            ? "All interfaces (idle)"
            : "Traffic on " + activeInterfaces.joined(separator: ", ")
    }

    // MARK: Internal bookkeeping (not observed)

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastByName: [String: InterfaceCounter] = [:]
    @ObservationIgnored private var lastTime: Date?

    /// Current sampling interval in whole seconds (FR-9, 1–5 s; default 1 s per
    /// FR-9a). Drives both the timer cadence and the history buffer's capacity;
    /// `start(intervalSeconds:)` and `setInterval(seconds:)` keep it in sync.
    @ObservationIgnored private var intervalSeconds: Int = 1

    /// Throughput (Mbps) above which an interface is named as "active" this tick,
    /// so background chatter of a few bytes doesn't clutter the source label.
    private static let activeThresholdMbps = 0.1

    // MARK: Lifecycle

    /// Begins sampling every `intervalSeconds` seconds (FR-9, 1–5 s; default 1 s
    /// per FR-9a). Safe to call repeatedly — `setInterval(seconds:)` reuses it to
    /// re-arm at a new rate: each call re-primes the baseline so the first sample
    /// is a real delta rather than a spike measured from zero, and rebuilds the
    /// history buffer to the capacity that keeps the graph a full 60-second window
    /// at this interval (so changing the rate restarts the graph — FR-7).
    func start(intervalSeconds: Int = 1) {
        stop()

        self.intervalSeconds = intervalSeconds
        history = RingBuffer<SpeedSample>(capacity: Self.historyCapacity(forIntervalSeconds: intervalSeconds))
        lastByName = Self.physicalCountersByName()
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
        let current = Self.physicalCountersByName()

        let elapsed = now.timeIntervalSince(lastTime ?? now)
        guard elapsed > 0 else { return }

        // Sum per-interval deltas across all physical interfaces (FR-10, v0.4).
        var deltaIn: UInt64 = 0
        var deltaOut: UInt64 = 0
        var contributors: [String] = []

        for (name, cur) in current {
            guard let prev = lastByName[name] else { continue }   // interface just appeared
            var dIn: UInt64 = 0
            var dOut: UInt64 = 0
            if cur.bytesIn  >= prev.bytesIn  { dIn  = cur.bytesIn  - prev.bytesIn  }   // else: wrapped/reset → 0
            if cur.bytesOut >= prev.bytesOut { dOut = cur.bytesOut - prev.bytesOut }
            deltaIn  &+= dIn
            deltaOut &+= dOut

            let ifaceMbps = Double(dIn &+ dOut) * 8.0 / elapsed / 1_000_000.0
            if ifaceMbps > Self.activeThresholdMbps { contributors.append(name) }
        }

        // Mbps = megabits/s (bytes × 8 ÷ 1e6). MBps derives as Mbps ÷ 8 (FR-5).
        let down = Double(deltaIn)  * 8.0 / elapsed / 1_000_000.0
        let up   = Double(deltaOut) * 8.0 / elapsed / 1_000_000.0

        // Publish for the UI (Increment 2.1).
        downMbps = down
        upMbps = up
        activeInterfaces = contributors.sorted()

        // Append to the rolling 60-second history for the graph (Increment 2.2).
        history.append(SpeedSample(time: now, downMbps: down, upMbps: up))

        lastByName = current
        lastTime = now
    }

    /// Current byte counters for physical interfaces (BSD `en*`), keyed by name.
    /// Loopback and virtual/VPN interfaces are excluded (see the type comment).
    private static func physicalCountersByName() -> [String: InterfaceCounter] {
        var map: [String: InterfaceCounter] = [:]
        for c in NetworkCounters.readAll() where c.name.hasPrefix("en") {
            map[c.name] = c
        }
        return map
    }
}
