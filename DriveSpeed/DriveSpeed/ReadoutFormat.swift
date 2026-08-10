//
//  ReadoutFormat.swift
//  DriveSpeed
//
//  Increment 2.3 — number formatting for the "X.X MB/s" readout (FR-6). Kept
//  free of SwiftUI so the fixed-width field logic can be unit-tested headlessly.
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
