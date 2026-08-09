//
//  SpeedPalette.swift
//  DriveSpeed
//
//  Increment 2.3 — shared download/upload color scheme.
//

import SwiftUI

/// Single source of truth for the download/upload colors, matching Apple's
/// Activity Monitor network graph: **blue for data in** (download / reads) and
/// **red for data out** (upload / writes). Used by both the readout arrows and
/// the graph lines so they always agree. System dynamic colors, so they adapt to
/// light/dark automatically (NFR-5).
enum SpeedPalette {
    /// Download — packets in / reads.
    static let down = Color.blue
    /// Upload — packets out / writes.
    static let up = Color.red
}
