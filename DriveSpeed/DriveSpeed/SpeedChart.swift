//
//  SpeedChart.swift
//  DriveSpeed
//
//  Increment 2.2 — the 60-second rolling throughput graph (FR-7).
//  Increment 2.3 — axis labels (X: 60s…now, Y: Mbps) and distinct line colors.
//  Increment 5.2a — reimplemented on SwiftUI `Canvas` (was SwiftUI `Charts`) to cut
//  the once-per-second render cost and its associated memory growth. A `sample` of
//  the Release build showed each 1 Hz Charts re-render costing ~24 ms of main-thread
//  work (NSHostingView layout + SwiftUI view-graph updates + Charts internals) — about
//  97% of the app's CPU. `Canvas` paints two `Path`s directly: no view-graph diffing,
//  no GeometryReader layout passes, no per-render metadata/hashable churn. Pure SwiftUI;
//  the `SpeedChart(samples:)` interface is unchanged.
//

import SwiftUI

/// The 60-second rolling throughput graph (FR-7): two line series — download and
/// upload (FR-7b) — over the most recent samples, drawn with `Canvas`. The x-axis
/// spans the last 60 seconds (FR-7a), so as new samples arrive the plot scrolls
/// left and the oldest samples fall off the edge.
struct SpeedChart: View {
    let samples: [SpeedSample]

    // Insets that reserve room around the line area for the axis labels.
    private let leftInset: CGFloat = 36    // y-axis value labels
    private let rightInset: CGFloat = 18   // so the "now" label isn't clipped
    private let topInset: CGFloat = 18     // "Mbps" unit + top gridline label
    private let bottomInset: CGFloat = 16  // "60s" / "now" labels

    var body: some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                draw(into: context, size: size)
            }
            legend
        }
    }

    // MARK: Drawing

    private func draw(into context: GraphicsContext, size: CGSize) {
        let plotLeft = leftInset
        let plotRight = size.width - rightInset
        let plotTop = topInset
        let plotBottom = size.height - bottomInset
        guard plotRight > plotLeft, plotBottom > plotTop else { return }

        // Secondary-styled caption label helper (adapts to light/dark, NFR-5).
        func label(_ string: String, at point: CGPoint, anchor: UnitPoint) {
            var text = context.resolve(Text(string).font(.caption2))
            text.shading = .style(.secondary)
            context.draw(text, at: point, anchor: anchor)
        }

        // X domain: the most recent 60 seconds, ending at the newest sample (or now
        // when empty) so the plot scrolls left as time advances (FR-7a).
        let end = samples.last?.time ?? Date()
        let start = end.addingTimeInterval(-60)
        func xFor(_ time: Date) -> CGFloat {
            let frac = CGFloat(time.timeIntervalSince(start) / 60)
            return plotLeft + frac * (plotRight - plotLeft)
        }

        // Y domain: 0 pinned at the bottom so idle reads as a flat baseline, auto-
        // scaled up to a "nice" ceiling ≥ the data max, with ~3 gridlines.
        let dataMax = samples.reduce(0.0) { Swift.max($0, Swift.max($1.readMBps, $1.writeMBps)) }
        let gridValues = Self.yGridValues(dataMax: dataMax)
        let yMax = gridValues.last ?? 1
        func yFor(_ value: Double) -> CGFloat {
            let frac = CGFloat(value / yMax)
            return plotBottom - frac * (plotBottom - plotTop)
        }

        // Gridlines + y-axis value labels.
        for value in gridValues {
            let y = yFor(value)
            var gridline = Path()
            gridline.move(to: CGPoint(x: plotLeft, y: y))
            gridline.addLine(to: CGPoint(x: plotRight, y: y))
            context.stroke(gridline, with: .color(.gray.opacity(0.22)), lineWidth: 0.5)
            label(Self.axisLabel(value), at: CGPoint(x: plotLeft - 4, y: y), anchor: .trailing)
        }

        // Unit + x-axis endpoint labels ("60s" left, "now" right — FR-7a).
        label("Mbps", at: CGPoint(x: 2, y: 1), anchor: .topLeading)
        label("60s", at: CGPoint(x: plotLeft, y: size.height - 1), anchor: .bottomLeading)
        label("now", at: CGPoint(x: plotRight, y: size.height - 1), anchor: .bottomTrailing)

        // The two line series (FR-7b), colored via the shared palette (NFR-5).
        // Needs at least two points to draw a segment.
        guard samples.count >= 2 else { return }
        context.stroke(
            linePath(samples.map { CGPoint(x: xFor($0.time), y: yFor($0.readMBps)) }),
            with: .color(SpeedPalette.down), lineWidth: 1.5
        )
        context.stroke(
            linePath(samples.map { CGPoint(x: xFor($0.time), y: yFor($0.writeMBps)) }),
            with: .color(SpeedPalette.up), lineWidth: 1.5
        )
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    // MARK: Legend (static — constant content, so it isn't re-evaluated per tick)

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(color: SpeedPalette.down, label: "Download")
            legendItem(color: SpeedPalette.up, label: "Upload")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
        }
    }

    // MARK: Y-axis scaling (pure — headless-tested)

    /// "Nice" y-axis gridline values from 0 up to a rounded ceiling ≥ `dataMax`,
    /// aiming for ~3 lines. Falls back to `[0, 1]` for the idle/empty case so the
    /// axis is never degenerate (NFR-4).
    static func yGridValues(dataMax: Double) -> [Double] {
        guard dataMax > 0, dataMax.isFinite else { return [0, 1] }
        let step = niceCeil(dataMax / 2)
        guard step > 0 else { return [0, 1] }
        let top = (dataMax / step).rounded(.up) * step
        var values: [Double] = []
        var value = 0.0
        while value <= top + step * 0.25 {
            values.append(value)
            value += step
        }
        return values
    }

    /// Smallest "nice" number (1, 2, 2.5, 5, 10 × 10ⁿ) greater than or equal to `x`.
    private static func niceCeil(_ x: Double) -> Double {
        guard x > 0 else { return 1 }
        let exponent = floor(log10(x))
        let base = pow(10, exponent)
        let fraction = x / base                     // in [1, 10)
        let nice: Double = fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 2.5 ? 2.5 : fraction <= 5 ? 5 : 10
        return nice * base
    }

    /// Compact gridline label: whole numbers without decimals, small values with one.
    static func axisLabel(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value >= 10 || value == value.rounded() { return String(Int(value.rounded())) }
        return String(format: "%.1f", value)
    }
}
