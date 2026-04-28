import Keyboard
import SVAudio
import SVCore
import SwiftUI
import Tonic

/// Isomorphic sargam keyboard with equal-sized rectangular keys colored by swar.
///
/// Unlike the piano layout, every key has the same width, making interval
/// relationships visually obvious. Keys are colored using spectral mapping
/// from `SargamColorMap` (Sa=red through Ni=violet). Komal/tivra variants
/// use a darker shade of their base swar color.
///
/// ## Features
/// - Equal-sized keys in chromatic order (C2–C7)
/// - Spectral coloring by swar with komal/tivra darkening
/// - Devanagari labels on all keys
/// - Touch-to-play routed through `AudioEngineManager.shared.multiChannel`
/// - Pitch detection dual highlighting (blue=detected, green=touched, cyan=both)
/// - Optional raga filtering (future: show only notes in selected raga)
struct IsomorphicSargamView: View {
    // MARK: - Input Properties

    /// MIDI notes currently highlighted by pitch detection (external source).
    let activeMidiNotes: Set<Int>

    /// Cents offset for tuning accuracy color on detected notes.
    let activeCentsOffset: Double

    /// Whether latching mode is enabled (keys stay held until retapped).
    var isLatchingEnabled: Bool = false

    // MARK: - Internal State

    /// MIDI notes currently held by touch (internal tracking for dual highlighting).
    @State private var touchedMidiNotes: Set<Int> = []

    /// Whether the SoundFont has been loaded yet.
    @State private var isSoundFontLoaded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Constants

    /// Devanagari labels indexed by chromatic position (0 = Sa/C, 1 = Komal Re/Db, ...).
    private static let devanagariLabels = [
        "सा", "रे♭", "रे", "ग♭", "ग", "म", "म♯", "प", "ध♭", "ध", "नि♭", "नि",
    ]

    /// Base swar name for SargamColorMap lookup, indexed by chromatic position.
    private static let baseSwarNames = [
        "Sa", "Re", "Re", "Ga", "Ga", "Ma", "Ma", "Pa", "Dha", "Dha", "Ni", "Ni",
    ]

    /// Whether the note at this chromatic index is a komal or tivra variant.
    private static let isVariant = [
        false, true, false, true, false, false, true, false, true, false, true, false,
    ]

    // MARK: - Body

    var body: some View {
        if ProcessInfo.processInfo.isiOSAppOnMac {
            // SP-6 Mac workaround — see InteractivePianoView.body for the
            // Tonic BitSet2x.forEach infinite-recursion bug on IOSSupport.
            RoundedRectangle(cornerRadius: 8)
                .fill(.tertiary.opacity(0.5))
                .frame(height: 80)
                .overlay {
                    Text("Sargam keyboard not yet available on Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Sargam keyboard (not available on Mac in this build)")
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                Keyboard(
                    layout: .isomorphic(pitchRange: Pitch(36) ... Pitch(96)),
                    latching: isLatchingEnabled,
                    noteOn: handleNoteOn,
                    noteOff: handleNoteOff
                ) { pitch, isActivated in
                    keyContent(pitch: pitch, isActivated: isActivated)
                }
            }
            .environment(\.layoutDirection, .leftToRight)
            .frame(height: 80)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Isomorphic sargam keyboard, 61 keys")
            .task {
                await loadSoundFontIfNeeded()
            }
        }
    }

    // MARK: - Key Content

    /// Custom key appearance with swar coloring and Devanagari labels.
    @ViewBuilder
    private func keyContent(pitch: Pitch, isActivated: Bool) -> some View {
        let midi = Int(pitch.midiNoteNumber)
        let noteIndex = ((midi - 60) % 12 + 12) % 12
        let highlight = highlightColor(for: midi)
        let hasHighlight = highlight != nil || isActivated

        let swarColor = swarBackgroundColor(noteIndex: noteIndex)
        let displayColor = highlight ?? (isActivated ? .green : swarColor)

        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(displayColor)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)

            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)

            VStack(spacing: 2) {
                Text(verbatim: Self.devanagariLabels[noteIndex])
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                let octave = Int(floor(Double(midi - 60) / 12.0)) + 4
                if noteIndex == 0 {
                    Text(verbatim: "\(octave)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(minWidth: 60, minHeight: 60)
        .scaleEffect(hasHighlight && !reduceMotion ? 1.05 : 1.0)
        .animation(
            reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7),
            value: hasHighlight
        )
        .accessibilityLabel(keyAccessibilityLabel(midi: midi, noteIndex: noteIndex))
        .accessibilityHint(isActivated ? "Currently playing" : "Double tap to play")
    }

    // MARK: - Colors

    /// Background color for a key based on its swar position.
    /// Komal/tivra variants are darkened versions of their base swar.
    private func swarBackgroundColor(noteIndex: Int) -> Color {
        let baseColor = SargamColorMap.color(for: Self.baseSwarNames[noteIndex])
        if Self.isVariant[noteIndex] {
            return baseColor.opacity(0.65)
        }
        return baseColor
    }

    // MARK: - Highlighting Logic

    /// Determine the highlight color for a key based on detection and touch state.
    private func highlightColor(for midiNote: Int) -> Color? {
        let isDetected = activeMidiNotes.contains(midiNote)
        let isTouched = touchedMidiNotes.contains(midiNote)

        switch (isDetected, isTouched) {
        case (true, true): return .cyan
        case (true, false): return .blue
        case (false, true): return .green
        case (false, false): return nil
        }
    }

    // MARK: - Callbacks

    /// Handle noteOn from AudioKit Keyboard.
    private func handleNoteOn(_ pitch: Pitch, _ point: CGPoint) {
        let midi = UInt8(clamping: Int(pitch.midiNoteNumber))
        touchedMidiNotes.insert(Int(midi))
        AudioEngineManager.shared.multiChannel?.playTouchNote(midi, velocity: 100)
    }

    /// Handle noteOff from AudioKit Keyboard.
    private func handleNoteOff(_ pitch: Pitch) {
        let midi = UInt8(clamping: Int(pitch.midiNoteNumber))
        touchedMidiNotes.remove(Int(midi))
        AudioEngineManager.shared.multiChannel?.stopTouchNote(midi)
    }

    // MARK: - SoundFont Loading

    /// Ensure the audio engine is running so touch input has a destination.
    /// Lazy-constructs `AudioEngineManager.shared.multiChannel` which preloads
    /// Acoustic Grand into `samplers[0]` for touch playback.
    private func loadSoundFontIfNeeded() async {
        guard !isSoundFontLoaded else { return }
        do {
            try AudioEngineManager.shared.startForPlayback()
            isSoundFontLoaded = true
        } catch {
            isSoundFontLoaded = false
        }
    }

    // MARK: - Accessibility

    /// Generate VoiceOver label for a key.
    private func keyAccessibilityLabel(midi: Int, noteIndex: Int) -> String {
        let octave = Int(floor(Double(midi - 60) / 12.0)) + 4
        let swar = Swar.allCases[noteIndex]
        return "\(AccessibilityHelper.swarLabel(for: swar.rawValue)), octave \(octave)"
    }
}

// MARK: - Previews

#Preview("Isomorphic Sargam — Idle") {
    IsomorphicSargamView(
        activeMidiNotes: [],
        activeCentsOffset: 0
    )
    .padding(.vertical)
}

#Preview("Isomorphic Sargam — C Major Chord") {
    IsomorphicSargamView(
        activeMidiNotes: [60, 64, 67],
        activeCentsOffset: 3
    )
    .padding(.vertical)
}
