//
//  ReadoutFormat.swift
//  DriveSpeed
//
//  Increment 2.3 — number formatting for the dual-unit readout (FR-6, format B:
//  "X.X Mbps (Y.Y MBps)"). Kept free of SwiftUI so the fixed-width field logic
//  can be unit-tested headlessly.
//

import Foundation

enum ReadoutFormat {

    /// Formats a value to one decimal place, right-justifying the integer part to
    /// `intDigits` using FIGURE SPACE (U+2007 — the same advance width as a
    /// tabular digit). Combined with a monospaced-digit font this keeps each
    /// field a constant width without zero-padding, so the readout doesn't shift
    /// as values change magnitude (NFR-3, FR-6). Values whose integer part
    /// exceeds `intDigits` simply render one character wider.
    ///
    /// `intDigits` defaults to 3, which covers gigabit (≤ 999.9 Mbps / 124.9 MBps)
    /// at a constant width; multi-gig peaks above 999.9 render slightly wider.
    static func field(_ value: Double, intDigits: Int = 3) -> String {
        let s = String(format: "%.1f", value)
        let intLen = s.firstIndex(of: ".").map {
            s.distance(from: s.startIndex, to: $0)
        } ?? s.count
        let pad = max(0, intDigits - intLen)
        return String(repeating: "\u{2007}", count: pad) + s
    }
}
