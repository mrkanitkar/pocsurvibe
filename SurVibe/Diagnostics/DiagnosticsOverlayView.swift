#if DEBUG
import SVAudio
import SwiftUI

/// Translucent debug overlay displaying real-time audio pipeline diagnostics.
///
/// Shows latency percentiles (p50/p95/p99), dropped frame count, buffer fill
/// level, and probe count sourced from a ``PerformanceSnapshot``. Gated behind
/// `#if DEBUG` and the `showDiagnostics` UserDefaults key so it never ships
/// to users.
///
/// ## Activation
/// Toggle in Settings or run in lldb:
/// ```
/// UserDefaults.standard.set(true, forKey: "showDiagnostics")
/// ```
///
/// ## Layout
/// Anchored to the top-trailing corner with Liquid Glass styling.
struct DiagnosticsOverlayView: View {

    // MARK: - Properties

    /// The performance snapshot data source. Updated by the parent view or
    /// a timer-driven refresh from the audio pipeline.
    let snapshot: PerformanceSnapshot

    /// Whether the diagnostics overlay is enabled via UserDefaults.
    @AppStorage("showDiagnostics") private var showDiagnostics = false

    // MARK: - Body

    var body: some View {
        if showDiagnostics {
            VStack(alignment: .leading, spacing: 4) {
                Text("Diagnostics")
                    .font(.caption2.bold())
                    .accessibilityLabel("Diagnostics panel header")

                Group {
                    latencyRow(
                        label: "p50",
                        micros: snapshot.latency.p50Micros,
                        accessibilityPrefix: "Median latency"
                    )
                    latencyRow(
                        label: "p95",
                        micros: snapshot.latency.p95Micros,
                        accessibilityPrefix: "95th percentile latency"
                    )
                    latencyRow(
                        label: "p99",
                        micros: snapshot.latency.p99Micros,
                        accessibilityPrefix: "99th percentile latency"
                    )
                }

                Divider()

                metricRow(
                    label: "Drops",
                    value: "\(snapshot.droppedFrames)",
                    accessibilityText: "\(snapshot.droppedFrames) dropped frames"
                )
                metricRow(
                    label: "Buffer",
                    value: "\(Int(snapshot.bufferFillLevel * 100))%",
                    accessibilityText: "Buffer fill level \(Int(snapshot.bufferFillLevel * 100)) percent"
                )
                metricRow(
                    label: "Probes",
                    value: "\(snapshot.probeCount)",
                    accessibilityText: "\(snapshot.probeCount) latency probes"
                )
            }
            .font(.system(.caption2, design: .monospaced))
            .padding(8)
            .glassEffect(.regular)
            .frame(maxWidth: 160)
        }
    }

    // MARK: - Private Helpers

    /// Render a single latency percentile row.
    ///
    /// Converts microseconds to milliseconds for human-readable display.
    ///
    /// - Parameters:
    ///   - label: Short label (e.g. "p50").
    ///   - micros: Latency value in microseconds.
    ///   - accessibilityPrefix: VoiceOver prefix before the ms value.
    private func latencyRow(
        label: String,
        micros: UInt64,
        accessibilityPrefix: String
    ) -> some View {
        let ms = Double(micros) / 1000.0
        return HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f ms", ms))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(accessibilityPrefix) \(String(format: "%.1f", ms)) milliseconds")
    }

    /// Render a generic metric row with label and value.
    ///
    /// - Parameters:
    ///   - label: Metric name.
    ///   - value: Formatted value string.
    ///   - accessibilityText: Full VoiceOver description.
    private func metricRow(
        label: String,
        value: String,
        accessibilityText: String
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
}
#endif
