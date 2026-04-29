// SurVibe/Play/QuantizeSheet.swift
import SVCore
import SwiftUI

/// Quantize-for-notation sub-sheet presented from ``ExportTakeSheet`` when the
/// user picks a notation format (MusicXML or MXL).
///
/// Captures the three pieces of musical context the ``Quantizer`` needs to map
/// wall-clock notes onto a beat grid: BPM, time signature, and grid resolution
/// (eighth- or sixteenth-note). A Tap Tempo helper averages the last three
/// inter-tap intervals into a BPM estimate so a user can dial in tempo
/// without a stepper.
///
/// SMF export does NOT route through this sheet — Standard MIDI Files preserve
/// real timestamps via the 60 BPM tempo meta in ``MIDISerializer.serializeType0``.
/// Notation requires a discrete grid, which is why only the score formats
/// trigger this sub-sheet.
///
/// On tap of **Export** the sheet calls `onContinue(bpm, ts, grid)` and
/// dismisses. On Cancel it calls `onCancel` (if provided) and dismisses
/// without invoking `onContinue`.
struct QuantizeSheet: View {
    /// Called with the user's chosen settings when **Export** is tapped.
    let onContinue: (Int, TimeSignature, QuantizeGrid) -> Void
    /// Optional cancel callback — fires when the user taps **Cancel**.
    var onCancel: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var bpm: Int = 80
    @State private var timeSignature: TimeSignature = .fourFour
    @State private var grid: QuantizeGrid = .sixteenth

    @State private var lastTapAt: Date?
    @State private var tapIntervals: [TimeInterval] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Tempo") {
                    Stepper(value: $bpm, in: 30...240) {
                        LabeledContent("BPM") {
                            Text(verbatim: "\(bpm)")
                                .monospacedDigit()
                        }
                    }
                    .accessibilityLabel("Beats per minute")
                    .accessibilityValue("\(bpm)")

                    Button {
                        registerTap()
                    } label: {
                        Label(tapTempoLabel, systemImage: "metronome")
                    }
                    .accessibilityLabel("Tap tempo")
                    .accessibilityHint(
                        "Tap repeatedly in time with the music. Three or more taps average to a tempo."
                    )
                }

                Section("Notation") {
                    Picker("Time signature", selection: $timeSignature) {
                        ForEach(TimeSignature.allCases, id: \.self) { ts in
                            Text(verbatim: ts.rawValue).tag(ts)
                        }
                    }
                    .accessibilityLabel("Time signature")

                    Picker("Grid", selection: $grid) {
                        Text(verbatim: "1/8").tag(QuantizeGrid.eighth)
                        Text(verbatim: "1/16").tag(QuantizeGrid.sixteenth)
                    }
                    .accessibilityLabel("Quantize grid resolution")
                    .accessibilityHint("Sets the smallest note value notes will snap to.")
                }

                Section("Preview") {
                    LabeledContent("Beat length") {
                        Text(beatLengthDescription).monospacedDigit()
                    }
                    LabeledContent("Grid step") {
                        Text(gridStepDescription).monospacedDigit()
                    }
                }
            }
            .navigationTitle("Quantize for notation")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        onContinue(bpm, timeSignature, grid)
                        dismiss()
                    }
                    .accessibilityLabel("Export with these settings")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel?()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Derived display

    private var beatLengthDescription: String {
        let ms = (60_000.0 / Double(bpm)).rounded()
        return "\(Int(ms)) ms"
    }

    private var gridStepDescription: String {
        let beatSec = 60.0 / Double(bpm)
        let ms = (beatSec * grid.beats * 1_000).rounded()
        return "\(Int(ms)) ms"
    }

    private var tapTempoLabel: String {
        if tapIntervals.isEmpty {
            return "Tap tempo"
        }
        return "Tap tempo (\(tapIntervals.count + 1) taps)"
    }

    // MARK: - Tap tempo

    /// Registers a tap, averaging the last three inter-tap intervals into a
    /// BPM estimate once at least two intervals have been collected.
    ///
    /// Resets if a tap arrives more than two seconds after the previous one
    /// — the user has probably stopped tapping and started again.
    private func registerTap() {
        let now = Date()
        if let last = lastTapAt {
            let interval = now.timeIntervalSince(last)
            if interval > 2.0 {
                tapIntervals.removeAll()
            } else {
                tapIntervals.append(interval)
                if tapIntervals.count > 3 {
                    tapIntervals.removeFirst(tapIntervals.count - 3)
                }
                if tapIntervals.count >= 2 {
                    let avg = tapIntervals.reduce(0, +) / Double(tapIntervals.count)
                    if avg > 0 {
                        let estimate = Int((60.0 / avg).rounded())
                        bpm = max(30, min(240, estimate))
                    }
                }
            }
        }
        lastTapAt = now
    }
}

#Preview {
    QuantizeSheet(onContinue: { _, _, _ in })
}
