// SurVibe/PlayAlong/LoopBuilderView.swift
import SwiftUI

/// Sheet content that lets the learner build a `LoopRegion` by picking a
/// 1-indexed inclusive measure range. Presented from the play-along
/// toolbar's "Loop" button when no region is currently active (Wave 5 E1).
///
/// The builder uses two `Stepper` controls clamped to
/// `1...totalMeasures` and enforces `start <= end` on each step. The
/// "Done" button calls `onCommit` with the final region; "Cancel"
/// dismisses without changing state. Both controls expose
/// `accessibilityLabel` / `accessibilityHint` for VoiceOver users.
struct LoopBuilderView: View {

    // MARK: - Properties

    /// Total measure count of the loaded arrangement. Used to clamp the
    /// stepper ranges. Falls back to `1` when the arrangement is empty so
    /// the steppers still render with a single valid value.
    let totalMeasures: Int

    /// Initial start measure (1-indexed, inclusive). Defaults to `1`.
    let initialStart: Int

    /// Initial end measure (1-indexed, inclusive). Defaults to
    /// `min(4, totalMeasures)`.
    let initialEnd: Int

    /// Invoked with a non-nil `LoopRegion` when the user taps "Done", or
    /// `nil` on "Cancel".
    let onCommit: (LoopRegion?) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var startMeasure: Int
    @State
    private var endMeasure: Int

    // MARK: - Initialization

    /// Create a loop builder.
    ///
    /// - Parameters:
    ///   - totalMeasures: Total number of measures in the arrangement.
    ///   - initialStart: Pre-selected start measure (1-indexed). Defaults
    ///     to `1`.
    ///   - initialEnd: Pre-selected end measure (1-indexed). Defaults to
    ///     `min(4, totalMeasures)` so a sensible 4-bar loop appears for
    ///     long songs.
    ///   - onCommit: Called with the final region (or `nil` on cancel).
    init(
        totalMeasures: Int,
        initialStart: Int = 1,
        initialEnd: Int? = nil,
        onCommit: @escaping (LoopRegion?) -> Void
    ) {
        let clampedTotal = max(1, totalMeasures)
        let start = min(max(1, initialStart), clampedTotal)
        let endCandidate = initialEnd ?? min(4, clampedTotal)
        let end = min(max(start, endCandidate), clampedTotal)
        self.totalMeasures = clampedTotal
        self.initialStart = start
        self.initialEnd = end
        _startMeasure = State(initialValue: start)
        _endMeasure = State(initialValue: end)
        self.onCommit = onCommit
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Loop region") {
                    startStepper
                    endStepper
                }
                Section {
                    summaryRow
                }
            }
            .navigationTitle("Loop builder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCommit(nil)
                        dismiss()
                    }
                    .accessibilityHint("Dismiss without setting a loop region")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let region = LoopRegion(
                            startMeasure: startMeasure,
                            endMeasure: endMeasure
                        )
                        onCommit(region)
                        dismiss()
                    }
                    .accessibilityHint(
                        "Set the loop to measures \(startMeasure) through \(endMeasure)"
                    )
                }
            }
        }
    }

    // MARK: - Subviews

    private var startStepper: some View {
        Stepper(
            value: Binding(
                get: { startMeasure },
                set: { newValue in
                    startMeasure = max(1, min(newValue, totalMeasures))
                    if endMeasure < startMeasure {
                        endMeasure = startMeasure
                    }
                }
            ),
            in: 1...totalMeasures
        ) {
            HStack {
                Text("Start measure")
                Spacer()
                Text(verbatim: "\(startMeasure)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Start measure")
        .accessibilityValue("Measure \(startMeasure)")
        .accessibilityHint("First measure of the loop, between 1 and \(totalMeasures)")
    }

    private var endStepper: some View {
        Stepper(
            value: Binding(
                get: { endMeasure },
                set: { newValue in
                    endMeasure = max(startMeasure, min(newValue, totalMeasures))
                }
            ),
            in: startMeasure...totalMeasures
        ) {
            HStack {
                Text("End measure")
                Spacer()
                Text(verbatim: "\(endMeasure)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("End measure")
        .accessibilityValue("Measure \(endMeasure)")
        .accessibilityHint(
            "Last measure of the loop, between \(startMeasure) and \(totalMeasures)"
        )
    }

    private var summaryRow: some View {
        HStack {
            Text("Looping")
            Spacer()
            Text(verbatim: "m.\(startMeasure)\u{2013}\(endMeasure)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Looping measures \(startMeasure) through \(endMeasure)"
        )
    }
}

#Preview("Loop builder") {
    LoopBuilderView(totalMeasures: 32) { _ in }
}
