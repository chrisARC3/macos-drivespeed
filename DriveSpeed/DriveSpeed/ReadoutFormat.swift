//
//  ReadoutFormat.swift
//  DriveSpeed
//
//  Increment 2.3 — number formatting for the "X.X MB/s" readout (FR-6). Kept
//  free of SwiftUI so the fixed-width field logic can be unit-tested headlessly.
//  Increment 2.4 — auto-scaling to KB/s below 1 MB/s (FR-6a), matching Activity
//  Monitor so the two agree at a glance.
//

import Foundation

enum ReadoutFormat {

    /// A throughput figure converted into whichever unit suits its magnitude.
    /// `value` is already expressed in `unit` — callers format `value` and append
    /// `unit`, they do not convert again.
    struct ScaledRate {
        let value: Double
        let unit: String
    }

    /// The unit a figure of this magnitude should be shown in, with the factor to
    /// multiply an MB/s value by (FR-6a).
    ///
    /// Below 1 MB/s we switch to KB/s, matching Activity Monitor. **1000, not
    /// 1024** — FR-5 fixes the decimal basis for this app, and mixing a binary
    /// kilobyte into a decimal megabyte would make the two tiers disagree at the
    /// boundary.
    ///
    /// Exposed separately from `scale(mbps:)` because the graph needs the unit for
    /// a whole axis — chosen once from the axis maximum — rather than per figure.
    static func unit(forMagnitude mbps: Double) -> (label: String, factor: Double) {
        mbps < 1.0 ? ("KB/s", 1000) : ("MB/s", 1)
    }

    /// Converts an MB/s figure into the unit that suits it (FR-6a).
    ///
    /// Each figure scales independently, so the readout can legitimately show
    /// "847.3 KB/s" for reads beside "2.4 MB/s" for writes — which is what
    /// Activity Monitor does, and is more informative than forcing a shared unit
    /// and rendering one of them as 0.8 or 0.0.
    ///
    /// The fixed-width field survives the switch: a KB/s figure is by definition
    /// under 1000 (1000 KB/s *is* 1 MB/s), so both tiers fit the same 4-digit
    /// field and the unit strings are both 4 characters. The readout therefore
    /// never shifts as a value crosses the boundary (NFR-3).
    static func scale(mbps: Double) -> ScaledRate {
        let u = unit(forMagnitude: mbps)
        return ScaledRate(value: mbps * u.factor, unit: u.label)
    }

    /// Formats a value to one decimal place, right-justifying the integer part to
    /// `intDigits` using FIGURE SPACE (U+2007 — the same advance width as a
    /// tabular digit). Combined with a monospaced-digit font this keeps each
    /// field a constant width without zero-padding, so the readout doesn't shift
    /// as values change magnitude (NFR-3, FR-6). Values whose integer part
    /// exceeds `intDigits` simply render one character wider.
    ///
    /// `intDigits` defaults to **4**, holding a constant width up to 9999.9 MB/s
    /// (about 10 GB/s). Widened from NetSpeed's 3 because disk figures routinely
    /// exceed 999.9 MB/s where network ones rarely did: a single USB4 enclosure
    /// measured 740 MB/s here, the internal SSD runs several times that, and FR-10
    /// sums both buses — so a 3-digit field would overflow constantly and defeat
    /// its own purpose. Values wider than `intDigits` still render, one character
    /// wider (NFR-3, FR-6).
    static func field(_ value: Double, intDigits: Int = 4) -> String {
        let s = String(format: "%.1f", value)
        let intLen = s.firstIndex(of: ".").map {
            s.distance(from: s.startIndex, to: $0)
        } ?? s.count
        let pad = max(0, intDigits - intLen)
        return String(repeating: "\u{2007}", count: pad) + s
    }
}
