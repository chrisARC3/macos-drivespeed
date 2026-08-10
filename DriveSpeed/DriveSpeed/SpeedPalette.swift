//
//  SpeedPalette.swift
//  DriveSpeed
//
//  Increment 2.3 — shared download/upload color scheme.
//

import SwiftUI

/// Single source of truth for the read/write colors, inherited unchanged from
/// NetSpeed and matching Activity Monitor's in/out sense: **blue for data in**
/// (bytes read off a drive) and **red for data out** (bytes written to one).
/// The mapping carried over without redefinition — a read is an "in" and a write
/// is an "out" — which is why this file needed no real change when the app
/// switched from network to disk.
///
/// Used by both the readout dots and the graph lines so they can never drift
/// apart. Since the in-chart legend was removed, those dots are the *only*
/// statement of the mapping — which makes sharing this one source of truth
/// load-bearing rather than merely tidy. System dynamic colors, so they adapt to
/// light/dark automatically (NFR-5).
enum SpeedPalette {
    /// Read — bytes in, off the drive.
    static let read = Color.blue
    /// Write — bytes out, onto the drive.
    static let write = Color.red
}
