import Keyboard
import SVAudio
import SVCore
import SwiftUI
import Tonic

/// Interactive 61-key piano keyboard with touch-to-play and pitch detection highlighting.
///
/// Wraps AudioKit Keyboard's `Keyboard` SwiftUI view with SurVibe-specific features:
/// - Devanagari labels and Western note names on each key
/// - SoundFont playback via SoundFontManager on touch
/// - Pitch detection highlighting (blue) from external `activeMidiNotes`
/// - Touch highlighting (green) from direct finger contact
/// - Dual highlighting (cyan) when both sources activate the same key
/// - Optional latching mode for chord building
///
/// ## Layout
/// Uses `Keyboard(.piano, pitchRange: Pitch(36)...Pitch(96))` for 61-key range (C2–C7).
/// Forces LTR layout direction for music notation correctness.
struct InteractivePianoView: View {
    // MARK: - Input Properties

    /// MIDI notes currently highlighted by pitch detection (external source).
    let activeMidiNotes: Set<Int>

    /// Isolated observable for MIDI keyboard highlight state.
    ///
    /// When provided (play-along mode), this view observes `HighlightState` directly
    /// so that CADisplayLink-driven key highlights (60–120 Hz) only re-render
    /// `InteractivePianoView` — NOT the parent `SongPlayAlongView` hierarchy.
    /// When `nil` (practice mode), falls back to `activeMidiNotes` alone.
    var highlightState: HighlightState?

    /// Cents offset for tuning accuracy color on detected notes.
    let activeCentsOffset: Double

    /// The expected next note to play, highlighted in amber/orange for guidance.
    /// Shown in guided free-play mode so the user knows which key to press.
    var expectedMidiNote: Int?

    /// Whether latching mode is enabled (keys stay held until retapped).
    var isLatchingEnabled: Bool = false

    /// Callback to clear all latched notes (called from parent view).
    var onClearLatched: (() -> Void)?

    /// Callback fired when a key is pressed, passing the MIDI note number.
    ///
    /// Used by play-along mode to route keyboard input to the scoring engine.
    /// Optional so existing call sites (Practice tab) are unaffected.
    var onNoteOn: ((Int) -> Void)?

    /// Callback fired when a key is released, passing the MIDI note number.
    ///
    /// Used by play-along mode to clear the key-press highlight in the sheet view.
    /// Optional so existing call sites (Practice tab) are unaffected.
    var onNoteOff: ((Int) -> Void)?

    /// Controls which label system is shown on white keys.
    ///
    /// Defaults to `.dual` so all existing call sites continue to show both
    /// Devanagari and Western labels without any changes at the call site.
    var notationMode: NotationDisplayMode = .dual

    /// Whether this view should eagerly load the SoundFont on appearance.
    ///
    /// Set to `false` when the parent view manages its own SoundFont loading
    /// (e.g. `SongPlayAlongView`), to avoid starting the engine in
    /// `.playbackOnly` mode before pitch detection has a chance to start it
    /// in `.playAndRecord` mode.
    var manageSoundFont: Bool = true

    // MARK: - Internal State

    /// MIDI notes currently held by touch (internal tracking for dual highlighting).
    @State private var touchedMidiNotes: Set<Int> = []

    /// Whether the SoundFont has been loaded yet.
    @State private var isSoundFontLoaded = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Constants

    /// Devanagari labels indexed by chromatic position (0 = Sa/C, 1 = Komal Re/Db, ...).
    private static let devanagariLabels = [
        "सा", "रे♭", "रे", "ग♭", "ग", "म", "म♯", "प", "ध♭", "ध", "नि♭", "नि"
    ]

    /// Western note names indexed by chromatic position.
    private static let westernNames = [
        "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"
    ]

    /// Natural (white key) chromatic offsets.
    private static let naturalOffsets: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    // MARK: - Body

    var body: some View {
        Keyboard(
            layout: .piano(pitchRange: Pitch(36) ... Pitch(96)),
            latching: isLatchingEnabled,
            noteOn: handleNoteOn,
            noteOff: handleNoteOff
        ) { pitch, isActivated in
            keyContent(pitch: pitch, isActivated: isActivated)
        }
        .environment(\.layoutDirection, .leftToRight)
        .frame(height: 160)
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: KeyPositionPreference.self,
                        value: Self.computeKeyPositions(
                            width: geo.size.width,
                            startMIDI: 36,
                            endMIDI: 96
                        )
                    )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Interactive piano keyboard, 61 keys")
        .task {
            if manageSoundFont {
                await loadSoundFontIfNeeded()
            }
        }
    }

    // MARK: - Key Content

    /// Custom key appearance with Devanagari labels, swar names, and dual highlighting.
    @ViewBuilder
    private func keyContent(pitch: Pitch, isActivated: Bool) -> some View {
        let midi = Int(pitch.midiNoteNumber)
        let noteIndex = ((midi - 60) % 12 + 12) % 12
        let isNatural = Self.naturalOffsets.contains(noteIndex)
        let highlight = highlightColor(for: midi)
        let hasHighlight = highlight != nil || isActivated

        ZStack {
            keyShape(isNatural: isNatural, highlight: highlight, isActivated: isActivated)
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

    /// Key background shape (white rounded rect or black bottom-rounded rect).
    @ViewBuilder
    private func keyShape(isNatural: Bool, highlight: Color?, isActivated: Bool) -> some View {
        if isNatural {
            RoundedRectangle(cornerRadius: 3)
                .fill(keyBackgroundColor(isNatural: true, highlight: highlight, isActivated: isActivated))
                .shadow(color: .black.opacity(0.1), radius: 1, y: 1)
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
        } else {
            UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 3)
                .fill(keyBackgroundColor(isNatural: false, highlight: highlight, isActivated: isActivated))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
        }
    }

    /// Labels for white keys.
    ///
    /// Respects `notationMode`:
    /// - `.sargam` / `.sargamPlusSheet`: Devanagari label only (no Western name)
    /// - `.western` / `.sheetMusic`: Western name + octave number only (no Devanagari)
    /// - `.dual` (default): Western name above, Devanagari below (existing behavior)
    private func whiteKeyLabels(midi: Int, noteIndex: Int, hasHighlight: Bool) -> some View {
        let octave = Int(floor(Double(midi - 60) / 12.0)) + 4
        let westernName = Self.westernNames[noteIndex]
        let westernLabel = noteIndex == 0 ? "\(westernName)\(octave)" : westernName

        return VStack(spacing: 1) {
            Spacer()
            switch notationMode {
            case .sargam, .sargamPlusSheet:
                Text(verbatim: Self.devanagariLabels[noteIndex])
                    .font(.system(size: 10, weight: hasHighlight ? .bold : .regular))
                    .foregroundStyle(hasHighlight ? .white : .primary)
            case .western, .sheetMusic:
                Text(verbatim: westernLabel)
                    .font(.system(size: 11, weight: hasHighlight ? .bold : (noteIndex == 0 ? .semibold : .regular)))
                    .foregroundStyle(hasHighlight ? .white : .primary)
            case .dual:
                Text(verbatim: westernLabel)
                    .font(.system(size: 11, weight: hasHighlight ? .bold : (noteIndex == 0 ? .semibold : .regular)))
                    .foregroundStyle(hasHighlight ? .white : .primary)
                Text(verbatim: Self.devanagariLabels[noteIndex])
                    .font(.system(size: 9))
                    .foregroundStyle(hasHighlight ? .white.opacity(0.9) : .secondary)
            }
            Spacer().frame(height: 6)
        }
    }

    // MARK: - Highlighting Logic

    /// Determine the highlight color for a key based on detection and touch state.
    ///
    /// When `highlightState` is set, MIDI keyboard highlights are read from there
    /// (isolated observation — does not cause the parent view to re-render).
    /// `activeMidiNotes` covers mic and touch-highlight fallbacks.
    ///
    /// - Returns: Blue for detection-only, green for touch-only, cyan for both, nil for none.
    private func highlightColor(for midiNote: Int) -> Color? {
        let isMIDIHighlighted = highlightState?.midiHighlightNotes.contains(midiNote) ?? false
        let isDetected = isMIDIHighlighted || activeMidiNotes.contains(midiNote)
        let isTouched = touchedMidiNotes.contains(midiNote)
        let isExpected = expectedMidiNote == midiNote

        switch (isDetected, isTouched) {
        case (true, true): return .cyan
        case (true, false): return .blue
        case (false, true): return .green
        case (false, false):
            return isExpected ? .orange : nil
        }
    }

    /// Compute the background fill color for a key.
    private func keyBackgroundColor(isNatural: Bool, highlight: Color?, isActivated: Bool) -> Color {
        if let highlight {
            return highlight
        }
        if isActivated {
            return .green
        }
        return isNatural ? .white : Color(white: 0.12)
    }

    // MARK: - Callbacks

    /// Handle noteOn from AudioKit Keyboard.
    ///
    /// Plays the note via SoundFont and notifies the parent view (if a callback
    /// is provided) so that play-along scoring can process the input.
    private func handleNoteOn(_ pitch: Pitch, _ point: CGPoint) {
        let midi = UInt8(clamping: Int(pitch.midiNoteNumber))
        touchedMidiNotes.insert(Int(midi))
        SoundFontManager.shared.playNote(midiNote: midi, velocity: 100)
        onNoteOn?(Int(midi))
    }

    /// Handle noteOff from AudioKit Keyboard.
    private func handleNoteOff(_ pitch: Pitch) {
        let midi = UInt8(clamping: Int(pitch.midiNoteNumber))
        touchedMidiNotes.remove(Int(midi))
        SoundFontManager.shared.stopNote(midiNote: midi)
        onNoteOff?(Int(midi))
    }

    /// Clear all latched notes, stopping their audio.
    func clearAllLatched() {
        for midi in touchedMidiNotes {
            SoundFontManager.shared.stopNote(midiNote: UInt8(clamping: midi))
        }
        touchedMidiNotes.removeAll()
    }

    // MARK: - Key Position Computation

    /// Compute center-X positions for all keys in the piano range.
    ///
    /// Uses the standard piano layout geometry to calculate each key's
    /// horizontal center position. White keys are evenly spaced; black keys
    /// sit between their adjacent white keys at the boundary.
    ///
    /// - Parameters:
    ///   - width: Total keyboard width in points.
    ///   - startMIDI: First MIDI note (inclusive).
    ///   - endMIDI: Last MIDI note (inclusive).
    /// - Returns: Array of `KeyPosition` values for all keys in range.
    nonisolated private static func computeKeyPositions(
        width: CGFloat,
        startMIDI: Int,
        endMIDI: Int
    ) -> [KeyPosition] {
        // Local copy avoids referencing @MainActor-isolated static property
        let naturals: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
        let whiteKeyCount = (startMIDI...endMIDI)
            .filter { naturals.contains((($0 - 60) % 12 + 12) % 12) }
            .count
        guard whiteKeyCount > 0 else { return [] }
        let whiteKeyWidth = width / CGFloat(whiteKeyCount)

        var positions: [KeyPosition] = []
        var whiteKeyIndex = 0

        for midi in startMIDI...endMIDI {
            let noteIndex = ((midi - 60) % 12 + 12) % 12
            let isNatural = naturals.contains(noteIndex)

            if isNatural {
                let centerX = (CGFloat(whiteKeyIndex) + 0.5) * whiteKeyWidth
                positions.append(KeyPosition(midiNote: UInt8(midi), centerX: centerX))
                whiteKeyIndex += 1
            } else {
                // Black key center sits at the boundary between adjacent white keys
                let centerX = CGFloat(whiteKeyIndex) * whiteKeyWidth
                positions.append(KeyPosition(midiNote: UInt8(midi), centerX: centerX))
            }
        }
        return positions
    }

    // MARK: - SoundFont Loading

    /// Eagerly load the bundled piano SoundFont on first appearance.
    private func loadSoundFontIfNeeded() async {
        guard !isSoundFontLoaded else { return }
        do {
            try await SoundFontManager.shared.loadBundledPiano()
            isSoundFontLoaded = true
        } catch {
            // Non-fatal: keyboard touch will still work, just no sound
            isSoundFontLoaded = false
        }
    }

    // MARK: - Accessibility

    /// Generate VoiceOver label for a key.
    private func keyAccessibilityLabel(midi: Int, noteIndex: Int) -> String {
        let octave = Int(floor(Double(midi - 60) / 12.0)) + 4
        let westernName = Self.westernNames[noteIndex]
        let swar = Swar.allCases[noteIndex]
        return "\(westernName)\(octave), \(AccessibilityHelper.swarLabel(for: swar.rawValue))"
    }
}

// MARK: - Previews

#Preview("Interactive Piano — Idle") {
    InteractivePianoView(
        activeMidiNotes: [],
        activeCentsOffset: 0
    )
    .padding(.vertical)
}

#Preview("Interactive Piano — C4 Detected") {
    InteractivePianoView(
        activeMidiNotes: [60],
        activeCentsOffset: 2
    )
    .padding(.vertical)
}

#Preview("Interactive Piano — Latching Mode") {
    InteractivePianoView(
        activeMidiNotes: [60, 64, 67],
        activeCentsOffset: 0,
        isLatchingEnabled: true
    )
    .padding(.vertical)
}
