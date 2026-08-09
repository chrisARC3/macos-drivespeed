//
//  ContentView.swift
//  DriveSpeed
//
//  Created by Christopher Karr on 7/10/26.
//

import SwiftUI

struct ContentView: View {
    // Persisted sampling interval in seconds (FR-9, 1–5 s; default 1 s per FR-9a).
    // @AppStorage is the SwiftUI-idiomatic UserDefaults binding (requirements §6),
    // so the chosen rate is remembered across launches (FR-9c) with no extra code.
    @AppStorage("samplingIntervalSeconds") private var samplingInterval = 1

    // Owns the sampler for the view's lifetime; @State is the right ownership
    // for an @Observable model. The view re-renders when the model's published
    // values change (Increment 2.1).
    @State private var sampler = SpeedSampler()

    var body: some View {
        VStack(spacing: 12) {
            // Numbers on top (FR-17), horizontally centered in the window and
            // staying centered as it resizes (v0.5). Format B and fixed-width
            // fields live in SpeedReadout (Increment 2.3).
            SpeedReadout(downMbps: sampler.downMbps, upMbps: sampler.upMbps)

            // 60-second rolling graph (FR-7) directly beneath the numbers.
            SpeedChart(samples: sampler.history.elements)
                .frame(minHeight: 120)

            // Bottom row: which physical interface(s) are carrying traffic (a small
            // footnote) on the left, and the sampling-rate control on the right.
            // Sharing one row keeps the numbers-on-top / graph-below layout (FR-17)
            // and adds almost no height — the reason for choosing the compact menu.
            HStack {
                Text(sampler.sourceText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                // Sampling interval (FR-9, 1–5 s) as an inline labeled menu. Inline
                // rather than a toolbar item so it can never collapse into the
                // toolbar's overflow "»" at small window widths, and so it reads
                // clearly via the timer icon + "Sample:" label (Increment 4.1
                // revision). The inline Picker fills the menu with the five choices,
                // check-marking the current one.
                Menu {
                    Picker("Sampling interval", selection: $samplingInterval) {
                        ForEach(1...5, id: \.self) { seconds in
                            Text(secondsLabel(seconds)).tag(seconds)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sample: \(secondsLabel(samplingInterval))", systemImage: "timer")
                }
                .controlSize(.small)
                .fixedSize()
                .help("How often to sample network throughput (seconds)")
            }
        }
        .padding()
        .frame(minWidth: 320)
        .onAppear {
            // Increment 1.1 — one-shot console snapshot proving we can read the
            // block-storage byte counters (FR-8). Temporary scaffolding, removed
            // in the Phase 2 cleanup just as NetSpeed's equivalent was. The
            // sampler below still reads *network* counters until Increment 1.2.
            DriveCounters.printSnapshot()
            sampler.start(intervalSeconds: samplingInterval)
        }
        .onDisappear { sampler.stop() }
        // Apply a rate change immediately (FR-9c): the timer re-arms at the new
        // interval and the graph resizes to keep its 60-second window.
        .onChange(of: samplingInterval) { _, newValue in
            sampler.setInterval(seconds: newValue)
        }
    }

    /// The interval spelled out with the correct singular/plural unit for the
    /// sampling-rate menu — "1 second", "2 seconds", … (FR-9). Only 1 is singular.
    private func secondsLabel(_ seconds: Int) -> String {
        "\(seconds) second\(seconds == 1 ? "" : "s")"
    }
}

#Preview {
    ContentView()
}
