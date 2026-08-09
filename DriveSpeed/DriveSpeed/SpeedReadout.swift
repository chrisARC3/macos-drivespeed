//
//  SpeedReadout.swift
//  DriveSpeed
//
//  Increment 2.3 — the centered dual-unit numeric readout (FR-6 format B, FR-17).
//

import SwiftUI

/// The download/upload readout: two rows (Down / Up), each showing
/// "X.X Mbps (Y.Y MBps)" (FR-6, format B — Mbps primary, MBps a secondary
/// parenthetical). Rendered with tabular digits in fixed-width fields so the
/// numbers don't shift as they change magnitude (NFR-3), and centered as a block
/// in the window, staying centered as it resizes (FR-17, v0.5).
///
/// The direction labels are right-aligned and ordered word-then-arrow, so the
/// words line up under each other and the fixed-width arrows align vertically in
/// a column beside the numbers. Each arrow is tinted with the shared blue/red
/// scheme (SpeedPalette) so it matches its line in the graph.
struct SpeedReadout: View {
    let downMbps: Double
    let upMbps: Double

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
            GridRow {
                label("Down", systemImage: "arrow.down", tint: SpeedPalette.down)
                    .gridColumnAlignment(.trailing)   // right-align the label column
                value(mbps: downMbps)
            }
            GridRow {
                label("Up", systemImage: "arrow.up", tint: SpeedPalette.up)
                value(mbps: upMbps)
            }
        }
        .font(.title3)
        // Span the full width so the block sits centered in the window and
        // re-centers on resize; the fixed-width fields keep it from jittering.
        .frame(maxWidth: .infinity)
    }

    /// A direction label: the word followed by a color-tinted arrow (matching its
    /// graph line). Word first, arrow second, so that under the column's trailing
    /// alignment the fixed-width arrows land in the same spot on both rows and
    /// align vertically. Only the arrow is tinted; the word stays in the default
    /// foreground for legibility.
    private func label(_ text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: systemImage)
                .foregroundStyle(tint)
        }
    }

    /// One direction's readout: primary "X.X Mbps" plus a de-emphasized
    /// "(Y.Y MBps)" secondary (MBps = Mbps ÷ 8, FR-5). Two Text views (not a
    /// concatenation) so each can carry its own foreground style; both use
    /// tabular digits over `ReadoutFormat`'s fixed-width fields.
    private func value(mbps: Double) -> some View {
        HStack(spacing: 0) {
            Text(ReadoutFormat.field(mbps) + " Mbps")
                .monospacedDigit()
            Text(" (" + ReadoutFormat.field(mbps / 8.0) + " MBps)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
