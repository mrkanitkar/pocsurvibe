import SVAudio
import SVCore
import SwiftUI

// MARK: - Pitch Feedback & Guided Play Subviews

extension SongPlayAlongView {
    // MARK: - Pitch Feedback

    /// A compact horizontal bar showing the detected note name, cents deviation,
    /// confidence, and a `PitchProximityMeter` indicator.
    func pitchFeedbackBar(pitch: PitchResult) -> some View {
        let displayCents = pitch.ragaCentsOffset ?? pitch.centsOffset

        return HStack(spacing: 12) {
            detectedNoteSection(pitch: pitch)
            centsDeviationSection(displayCents: displayCents)

            PitchProximityMeter(
                centsOffset: displayCents,
                trackColor: themeManager.resolved.dividerColor,
                centerLineColor: themeManager.resolved.successColor
            )
            .frame(width: 24, height: 48)

            Spacer()

            confidenceSection(confidence: pitch.confidence)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    /// Detected note name with optional out-of-raga badge.
    @ViewBuilder
    private func detectedNoteSection(pitch: PitchResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Detected")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Text(pitch.noteName)
                    .font(.headline.bold())
                if pitch.isInRaga == false {
                    Text("Outside Raga")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.orange))
                        .accessibilityLabel("Note is outside the raga")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Detected note \(pitch.noteName)")
    }

    /// Cents deviation display column.
    @ViewBuilder
    private func centsDeviationSection(displayCents: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Cents")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%+.0f", displayCents))
                .font(.callout.monospacedDigit())
                .foregroundStyle(centsColor(displayCents))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Int(displayCents)) cents offset")
    }

    /// Confidence percentage display column.
    @ViewBuilder
    private func confidenceSection(confidence: Double) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("Confidence")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(Int(confidence * 100))%")
                .font(.callout.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Confidence \(Int(confidence * 100)) percent")
    }

    /// Map a cents offset to a feedback color.
    func centsColor(_ cents: Double) -> Color {
        let abs = Swift.abs(cents)
        if abs <= 10 { return .green }
        if abs <= 25 { return .blue }
        if abs <= 50 { return .orange }
        return .red
    }

    // MARK: - Guided Play Overlays

    /// Brief banner flashing green (correct) or red (wrong) after each note attempt.
    var correctnessBanner: some View {
        let isCorrect = correctnessBannerColor == .green
        return HStack(spacing: 8) {
            Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3.bold())
                .accessibilityHidden(true)
            Text(isCorrect ? "Correct!" : "Try again")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(correctnessBannerColor.gradient, in: Capsule())
        .accessibilityLabel(isCorrect ? "Correct note" : "Wrong note, try again")
    }

    /// Overlay shown when user hasn't played for `patienceSeconds`.
    func stuckHintOverlay(expectedMidiNote: Int) -> some View {
        let swarName = swarNameFromMIDI(expectedMidiNote)
        return VStack(spacing: 12) {
            Text("Play this note")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(swarName)
                .font(.largeTitle.bold())
                .foregroundStyle(.orange)
            HStack(spacing: 16) {
                Button {
                    withAnimation(reduceMotion ? .none : .default) {
                        viewModel.skipGuidedNote()
                    }
                } label: {
                    Label("Skip", systemImage: "forward.fill")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .accessibilityLabel("Skip this note")
                .accessibilityHint("Mark as missed and move to the next note")
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hint: play \(swarName)")
    }

    /// Convert a MIDI note number to a full swar name for the hint overlay.
    func swarNameFromMIDI(_ midiNote: Int) -> String {
        let semitone = midiNote % 12
        let swarNames = [
            "Sa", "Komal Re", "Re", "Komal Ga", "Ga", "Ma",
            "Tivra Ma", "Pa", "Komal Dha", "Dha", "Komal Ni", "Ni",
        ]
        let index = ((semitone % 12) + 12) % 12
        return swarNames[index]
    }

    // MARK: - Guided Play Actions

    /// Respond to guided play state transitions (correct/wrong flash).
    func handleGuidedPlayStateChange(_ newState: PlayAlongViewModel.GuidedPlayState) {
        switch newState {
        case .correct:
            flashCorrectnessBanner(color: .green, hideAfterMs: 500)
        case .wrong:
            flashCorrectnessBanner(color: .red, hideAfterMs: 400)
        case .waitingForNote, .stuck:
            withAnimation(reduceMotion ? .none : .default) { showCorrectnessBanner = false }
        }
    }

    /// Show the correctness banner briefly, then auto-hide.
    private func flashCorrectnessBanner(color: Color, hideAfterMs: Int) {
        correctnessBannerColor = color
        withAnimation(reduceMotion ? .none : .default) { showCorrectnessBanner = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(hideAfterMs))
            withAnimation(reduceMotion ? .none : .default) { showCorrectnessBanner = false }
        }
    }
}
