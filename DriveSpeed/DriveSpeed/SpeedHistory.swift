//
//  SpeedHistory.swift
//  DriveSpeed
//
//  Increment 2.2 — in-memory history backing the 60-second rolling graph.
//  A single sampled reading plus the fixed-capacity buffer that retains the
//  most recent readings. Held in memory only (FR-7 — nothing is written to disk).
//

import Foundation

/// One sampled throughput reading at a point in time. `time` drives the graph's
/// x-axis; `downMbps` / `upMbps` are the two line series (FR-7b).
struct SpeedSample: Identifiable {
    let id = UUID()
    let time: Date
    let downMbps: Double
    let upMbps: Double
}

/// A fixed-capacity FIFO buffer: appending beyond `capacity` evicts the oldest
/// element, so it always holds the most recent `capacity` items in oldest→newest
/// order. Backs the 60-second rolling graph (FR-7, FR-7a).
///
/// Value type on purpose: it lives as a property on the `@Observable`
/// `SpeedSampler`, so mutating it in place (`append`) registers as a change and
/// refreshes the SwiftUI view. For N = 60 at 1 Hz the `removeFirst` on eviction
/// is trivially cheap and keeps the elements naturally time-ordered for Charts.
struct RingBuffer<Element> {
    let capacity: Int
    private(set) var elements: [Element] = []

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        elements.reserveCapacity(capacity)
    }

    /// Appends `element`; if that pushes past `capacity`, drops oldest-first so
    /// only the most recent `capacity` elements remain.
    mutating func append(_ element: Element) {
        elements.append(element)
        if elements.count > capacity {
            elements.removeFirst(elements.count - capacity)
        }
    }

    /// Drops all elements — used to start a fresh sampling session (FR-7: history
    /// is transient and begins empty each run).
    mutating func removeAll() {
        elements.removeAll(keepingCapacity: true)
    }
}
