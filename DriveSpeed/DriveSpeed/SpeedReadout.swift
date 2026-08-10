//
//  SpeedReadout.swift
//  DriveSpeed
//
//  Increment 2.3 — the centered numeric readout (FR-6, FR-17).
//

import SwiftUI

/// The read/write readout: two rows (Read / Write), each showing a single
/// figure as "X.X MB/s" (FR-5, FR-6). Rendered with tabular digits in
/// fixed-width fields so the numbers don't shift as they change magnitude
/// (NFR-3), and centered as a block in the window, staying centered as it
/// resizes (FR-17).
///
/// **Single unit, unlike NetSpeed.** NetSpeed showed "X.X Mbps (Y.Y MBps)" —
/// megabits primary, because that is what ISP plans advertise, with megabytes as
/// a parenthetical for real transfer feel. Storage has no such split: drives,
/// enclosures, and benchmark tools all quote MB/s, so the megabit figure would
/// carry no information and only add clutter. Dropped on Chris's call.
///
/// The direction labels are right-aligned and ordered word-then-arrow, so the
/// words line up under each other and the fixed-width arrows align vertically in
/// a column beside the numbers. Each arrow is tinted with the shared blue/red
/// scheme (SpeedPalette) so it matches its line in the graph.
struct SpeedReadout: View {
    let readMBps: Double
    let writeMBps: Double

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                label("Read", tint: SpeedPalette.read)
                    .gridColumnAlignment(.trailing)   // right-align the label column
                value(readMBps)
            }
            GridRow {
                label("Write", tint: SpeedPalette.write)
                value(writeMBps)
            }
        }
        .font(.title3)
        // Span the full width so the block sits centered in the window and
        // re-centers on resize; the fixed-width fields keep it from jittering.
        .frame(maxWidth: .infinity)
    }

    /// A direction label: the word followed by a color-tinted dot matching its
    /// graph line.
    ///
    /// **The dots are the graph's colour key.** They replaced up/down arrows,
    /// which carried a network sense — packets in and out — that reads oddly for
    /// a drive, and which duplicated the chart's own legend. With the legend gone,
    /// these dots are the only place the blue/red mapping is stated, which is why
    /// they use the same `SpeedPalette` values as the lines rather than any local
    /// colour.
    ///
    /// Word first, dot second, so that under the column's trailing alignment the
    /// fixed-size dots land in the same spot on both rows and align vertically —
    /// which is why "Read" and "Write" being different lengths doesn't misalign
    /// them. Only the dot is tinted; the word stays in the default foreground for
    /// legibility.
    private func label(_ text: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(text)
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)
        }
    }

    /// One direction's readout to one decimal place (FR-6), auto-scaled to KB/s
    /// below 1 MB/s (FR-6a), in a tabular-digit fixed-width field so the layout
    /// holds steady — including across the unit boundary, since a KB/s figure is
    /// always under 1000 and both unit strings are four characters (NFR-3).
    private func value(_ mbps: Double) -> some View {
        let scaled = ReadoutFormat.scale(mbps: mbps)
        return Text(ReadoutFormat.field(scaled.value) + " " + scaled.unit)
            .monospacedDigit()
    }
}
