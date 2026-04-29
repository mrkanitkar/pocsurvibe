import Keyboard
import SVAudio
import SVCore
import SwiftUI
import Tonic

/// Finger-friendly horizontally-scrollable piano for the Play tab.
///
/// `InteractivePianoView` is shared with PlayAlong and Practice, where it
/// must fit its full key range into the available width to keep the falling-
/// notes view aligned with the keyboard. That sizes white keys at ~22pt on
/// iPad — too narrow for finger play.
///
/// `LargePianoView` is a Play-tab-only wrapper that:
/// - Pins each white key at a finger-friendly fixed stride (~50pt).
/// - Renders a wide playable range (C2..C8) inside a horizontal `ScrollView`
///   so the user can swipe between octaves like GarageBand.
/// - Auto-centers on middle C (C4) when the view first appears so the user
///   starts looking at the most useful region.
///
/// Touch playback is routed through `AudioEngineManager.shared.multiChannel`
/// — the same path `InteractivePianoView` uses — so behavior matches the
/// existing tabs. Highlighting from external MIDI input is driven by the
/// `activeMidiNotes` set fed from the display-link-bound highlight
/// coordinator.
struct LargePianoView: View {
    /// MIDI notes currently highlighted (driven by the Play tab's display-
    /// link-bound coordinator). Notes inside this set render with the touch
    /// highlight color regardless of finger contact.
    let activeMidiNotes: Set<Int>

    /// Callback fired when a key is pressed. Optional so the parent can drop
    /// it when only display is needed.
    var onNoteOn: ((Int) -> Void)?

    /// Callback fired when a key is released.
    var onNoteOff: ((Int) -> Void)?

    /// Lowest MIDI note (inclusive). Default `36` = C2.
    /// Capped at `36..<108` (73 keys) — see `InteractivePianoView` for the
    /// upstream Tonic / AudioKit-Keyboard generic-metadata stall that blocks
    /// wider ranges on iOS.
    var lowestMidi: Int = 36

    /// Highest MIDI note (inclusive). Default `108` = C8.
    var highestMidi: Int = 108

    /// White-key width in points. 50pt fits two octaves across a typical
    /// iPad-Air-landscape view and is comfortable for adult fingers.
    var whiteKeyWidth: CGFloat = 50

    @State
    private var touchedMidiNotes: Set<Int> = []

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// Devanagari labels indexed by chromatic position (0 = Sa/C).
    private static let devanagariLabels = [
        "सा", "रे♭", "रे", "ग♭", "ग", "म", "म♯", "प", "ध♭", "ध", "नि♭", "नि",
    ]

    /// Western note names indexed by chromatic position.
    private static let westernNames = [
        "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
    ]

    /// Natural (white key) chromatic offsets.
    private static let naturalOffsets: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    var body: some View {
        let whiteKeyCount = (lowestMidi...highestMidi)
            .filter { Self.naturalOffsets.contains((($0 - 60) % 12 + 12) % 12) }
            .count
        let keyboardWidth = CGFloat(whiteKeyCount) * whiteKeyWidth
        let range = Pitch(Int8(lowestMidi))...Pitch(Int8(highestMidi))

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                Keyboard(
                    layout: .piano(pitchRange: range),
                    noteOn: handleNoteOn,
                    noteOff: handleNoteOff
                ) { pitch, isActivated in
                    keyContent(pitch: pitch, isActivated: isActivated)
                        .id(Int(pitch.midiNoteNumber))
                }
                .frame(width: keyboardWidth)
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(
                    "Interactive piano keyboard, \(highestMidi - lowestMidi + 1) keys, swipe to scroll"
                )
            }
            .onAppear {
                // Center on middle C so the user starts looking at the
                // playable region instead of either end of the range.
                proxy.scrollTo(60, anchor: .center)
            }
        }
    }

    @ViewBuilder
    private func keyContent(pitch: Pitch, isActivated: Bool) -> some View {
        let midi = Int(pitch.midiNoteNumber)
        let noteIndex = ((midi - 60) % 12 + 12) % 12
        let isNatural = Self.naturalOffsets.contains(noteIndex)
        let highlight = highlightColor(for: midi, isActivated: isActivated)
        let hasHighlight = highlight != nil

        ZStack {
            keyShape(isNatural: isNatural, highlight: highlight)
            if isNatural {
                whiteKeyLabels(midi: midi, noteIndex: noteIndex, hasHighlight: hasHighlight)
            }
        }
        .scaleEffect(hasHighlight && !reduceMotion ? (isNatural ? 1.04 : 1.06) : 1.0)
        .animation(
            reduceMotion ? nil : .spring(response: 0.08, dampingFraction: 0.85),
            value: hasHighlight
        )
        .accessibilityLabel(keyAccessibilityLabel(midi: midi, noteIndex: noteIndex))
        .accessibilityHint(isActivated ? "Currently playing" : "Double tap to play")
    }

    @ViewBuilder
    private func keyShape(isNatural: Bool, highlight: Color?) -> some View {
        if isNatural {
            RoundedRectangle(cornerRadius: 3)
                .fill(keyBackgroundColor(isNatural: true, highlight: highlight))
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
        } else {
            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                .fill(keyBackgroundColor(isNatural: false, highlight: highlight))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
        }
    }

    private func whiteKeyLabels(midi: Int, noteIndex: Int, hasHighlight: Bool) -> some View {
        let octave = Int(floor(Double(midi - 60) / 12.0)) + 4
        let westernName = Self.westernNames[noteIndex]
        let westernLabel = noteIndex == 0 ? "\(westernName)\(octave)" : westernName

        return VStack(spacing: 1) {
            Spacer()
            Text(verbatim: westernLabel)
                .font(.system(size: 14, weight: hasHighlight ? .bold : (noteIndex == 0 ? .semibold : .regular)))
                .foregroundStyle(hasHighlight ? .white : .primary)
            Text(verbatim: Self.devanagariLabels[noteIndex])
                .font(.system(size: 11))
                .foregroundStyle(hasHighlight ? .white.opacity(0.9) : .secondary)
            Spacer().frame(height: 8)
        }
    }

    /// Color for a key combining external `activeMidiNotes` (MIDI input) and
    /// `touchedMidiNotes` (finger contact). Cyan when both sources active.
    private func highlightColor(for midi: Int, isActivated: Bool) -> Color? {
        let isDetected = activeMidiNotes.contains(midi)
        let isTouched = touchedMidiNotes.contains(midi) || isActivated
        switch (isDetected, isTouched) {
        case (true, true): return .cyan
        case (true, false): return .blue
        case (false, true): return .green
        case (false, false): return nil
        }
    }

    private func keyBackgroundColor(isNatural: Bool, highlight: Color?) -> Color {
        if let highlight { return highlight }
        return isNatural ? .white : Color(white: 0.12)
    }

    private func handleNoteOn(_ pitch: Pitch, _ point: CGPoint) {
        let midi = UInt8(clamping: Int(pitch.midiNoteNumber))
        touchedMidiNotes.insert(Int(midi))
        AudioEngineManager.shared.multiChannel?.playTouchNote(midi, velocity: 100)
        onNoteOn?(Int(midi))
    }

    private func handleNoteOff(_ pitch: Pitch) {
        let midi = UInt8(clamping: Int(pitch.midiNoteNumber))
        touchedMidiNotes.remove(Int(midi))
        AudioEngineManager.shared.multiChannel?.stopTouchNote(midi)
        onNoteOff?(Int(midi))
    }

    private func keyAccessibilityLabel(midi: Int, noteIndex: Int) -> String {
        let octave = Int(floor(Double(midi - 60) / 12.0)) + 4
        let westernName = Self.westernNames[noteIndex]
        let swar = Swar.allCases[noteIndex]
        return "\(westernName)\(octave), \(AccessibilityHelper.swarLabel(for: swar.rawValue))"
    }
}

#Preview("Large Piano — Idle") {
    LargePianoView(activeMidiNotes: [])
        .frame(height: 220)
        .padding(.vertical)
}

#Preview("Large Piano — C major triad") {
    LargePianoView(activeMidiNotes: [60, 64, 67])
        .frame(height: 220)
        .padding(.vertical)
}
