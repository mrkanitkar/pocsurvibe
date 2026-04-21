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
/// Uses `Keyboard(.piano, pitchRange:)` with a `GeometryReader`-driven adaptive range:
/// 61 keys (C2–C7) on narrow views, 73 keys (C2–C8) on medium, 88 keys (A0–C8) on wide.
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

    /// Color used to highlight right-hand MIDI notes (from `highlightState?.rhNotes`).
    ///
    /// Defaults to the Rang right-hand semantic token (P1-5) — colorblind-aware
    /// and WCAG AA compliant on white piano keys. Overridden by the active theme
    /// via `PlayAlongChromeState.updateTheme` in production flows.
    /// Passed as `let` to preserve the latency contract — no environment reads.
    var rhColor: Color = Color.rangRightHand

    /// Color used to highlight left-hand MIDI notes (from `highlightState?.lhNotes`).
    ///
    /// Defaults to the Rang left-hand semantic token (P1-5).
    var lhColor: Color = Color.rangLeftHand

    /// Color used to highlight chord / both-hands MIDI notes
    /// (from `highlightState?.chordNotes`, or notes present in both
    /// `rhNotes` and `lhNotes`).
    ///
    /// Defaults to the Rang both-hands semantic token (P1-5).
    var chordColor: Color = Color.rangBothHands

    // MARK: - Internal State

    /// MIDI notes currently held by touch (internal tracking for dual highlighting).
    @State
    private var touchedMidiNotes: Set<Int> = []

    /// Whether the SoundFont has been loaded yet.
    @State
    private var isSoundFontLoaded = false

    /// White-key stride used to compute adaptive breakpoints.
    ///
    /// Scales with Dynamic Type so that users who increase text size still
    /// see a layout that fits the available width.
    @ScaledMetric(relativeTo: .body)
    private var whiteKeyStride: CGFloat = 22

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// Colorblind-aware differentiation: when true, render an R/L/• letter
    /// overlay on top of highlighted keys so users who cannot distinguish
    /// the RH/LH/chord fill colors still perceive which hand the key belongs to.
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor

    // MARK: - Constants

    /// Devanagari labels indexed by chromatic position (0 = Sa/C, 1 = Komal Re/Db, ...).
    private static let devanagariLabels = [
        "सा", "रे♭", "रे", "ग♭", "ग", "म", "म♯", "प", "ध♭", "ध", "नि♭", "नि",
    ]

    /// Western note names indexed by chromatic position.
    private static let westernNames = [
        "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
    ]

    /// Natural (white key) chromatic offsets.
    private static let naturalOffsets: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            if ProcessInfo.processInfo.isiOSAppOnMac {
                // SP-6 workaround: Tonic 2.1.0 + AudioKit/Keyboard 1.4.1 have a
                // Swift generic-metadata infinite-recursion in BitSet2x.forEach
                // (BitSet.swift:134/135) when rendered under Mac's IOSSupport
                // Swift runtime. Stalls 98%+ CPU forever; app hangs. Bug is
                // reproducible at every pitch-range size, not just wide layouts.
                // Render a placeholder on Mac until Tonic ships a fix. Remove
                // this guard when upstream Tonic supports iOS-on-Mac.
                macPianoPlaceholder
            } else {
                let (loMidi, hiMidi) = Self.adaptiveMidiRange(
                    forWidth: proxy.size.width,
                    whiteKeyStride: whiteKeyStride
                )
                let range = Pitch(Int8(loMidi))...Pitch(Int8(hiMidi))
                let keyCount = hiMidi - loMidi + 1
                Keyboard(
                    layout: .piano(pitchRange: range),
                    latching: isLatchingEnabled,
                    noteOn: handleNoteOn,
                    noteOff: handleNoteOff
                ) { pitch, isActivated in
                    keyContent(pitch: pitch, isActivated: isActivated)
                }
                .environment(\.layoutDirection, .leftToRight)
                .overlay {
                    Color.clear
                        .preference(
                            key: KeyPositionPreference.self,
                            value: Self.computeKeyPositions(
                                width: proxy.size.width,
                                startMIDI: loMidi,
                                endMIDI: hiMidi
                            )
                        )
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Interactive piano keyboard, \(keyCount) keys")
            }
        }
        .frame(height: 160)
        .task {
            if manageSoundFont {
                await loadSoundFontIfNeeded()
            }
        }
    }

    /// Mac-only placeholder shown instead of Tonic's `Keyboard` view.
    /// See `body` comment for the Tonic bug this works around.
    private var macPianoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.tertiary.opacity(0.5))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "pianokeys")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Interactive piano not yet available on Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Interactive piano (not available on Mac in this build)")
    }

    /// Maps available view width to a playable pitch range.
    ///
    /// Breakpoints target ≥ `whiteKeyStride` per white key. 36/45 white keys
    /// are the natural breakpoints for 61/73-key pianos:
    /// - 61 keys = 36 white → ~792pt @ 22pt stride (default)
    /// - 73 keys = 45 white → ~990pt @ 22pt stride (iPad landscape / Mac)
    ///
    /// Note: The 88-key range (A0–C8) is currently capped at 73 keys due to a
    /// Swift generic-metadata stall in AudioKit/Keyboard 1.4.1 + Tonic 2.1.0
    /// that blocks the main thread and triggers a watchdog kill on wide layouts.
    ///
    /// - Parameters:
    ///   - width: Available view width in points.
    ///   - stride: Width per white key in points (scales with Dynamic Type).
    /// - Returns: A closed MIDI pitch range appropriate for the available width.
    nonisolated static func adaptivePitchRange(
        forWidth width: CGFloat,
        whiteKeyStride stride: CGFloat
    ) -> ClosedRange<Pitch> {
        let (lo, hi) = adaptiveMidiRange(forWidth: width, whiteKeyStride: stride)
        return Pitch(Int8(lo))...Pitch(Int8(hi))
    }

    /// Returns the raw MIDI note number bounds for the adaptive pitch range.
    ///
    /// Separated from `adaptivePitchRange` so the pure numeric logic can be
    /// unit-tested without requiring a Tonic import in the test target.
    ///
    /// - Parameters:
    ///   - width: Available view width in points.
    ///   - stride: Width per white key in points (scales with Dynamic Type).
    /// - Returns: A tuple `(lowerMidi, upperMidi)` of MIDI note numbers.
    nonisolated static func adaptiveMidiRange(
        forWidth width: CGFloat,
        whiteKeyStride stride: CGFloat
    ) -> (lowerMidi: Int, upperMidi: Int) {
        let width61 = stride * 36
        let width73 = stride * 45
        switch width {
        case ..<width61: return (36, 96)   // 61 keys — C2..C7
        case width61..<width73: return (36, 108)  // 73 keys — C2..C8
        // Capped at 73 keys: AudioKit/Keyboard 1.4.1 + Tonic 2.1.0 trigger a
        // Swift generic-metadata instantiation stall in PianoSpacer.whiteKeys
        // when the range exceeds ~73 keys, blocking the main thread long enough
        // for the watchdog to kill the app (0x8BADF00D). Cap until upstream fix.
        default: return (36, 108)  // 73 keys — C2..C8 (capped, was A0..C8)
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
            if differentiateWithoutColor, let letter = differentiateLetter(forMidi: midi) {
                Text(verbatim: letter)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Color.black.opacity(0.55), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
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
    /// Preference cascade for "detected" color:
    /// 1. If the note is in `highlightState.chordNotes`, or in BOTH `rhNotes`
    ///    AND `lhNotes`, use `chordColor`.
    /// 2. Else if in `highlightState.rhNotes`, use `rhColor`.
    /// 3. Else if in `highlightState.lhNotes`, use `lhColor`.
    /// 4. Else fall back to the existing blue (detection only).
    ///
    /// Touch, expected-note, and dual states are preserved unchanged.
    ///
    /// - Returns: Hand/chord color or blue for detection-only, green for touch-only,
    ///   cyan for both detection+touch, orange for the expected next note,
    ///   nil for none.
    private func highlightColor(for midiNote: Int) -> Color? {
        let rh = highlightState?.rhNotes ?? []
        let lh = highlightState?.lhNotes ?? []
        let chord = highlightState?.chordNotes ?? []

        let isMIDIHighlighted = highlightState?.midiHighlightNotes.contains(midiNote) ?? false
        let isDetected = isMIDIHighlighted || activeMidiNotes.contains(midiNote)
        let isTouched = touchedMidiNotes.contains(midiNote)
        let isExpected = expectedMidiNote == midiNote

        // Resolve the "detected" color with the RH/LH/chord cascade.
        // When none of the hand sets contain the note, defaults to blue so
        // existing callers that don't populate `rhNotes / lhNotes / chordNotes`
        // continue to see the legacy single-color highlight.
        let detectedColor: Color = {
            if chord.contains(midiNote) { return chordColor }
            if rh.contains(midiNote) && lh.contains(midiNote) { return chordColor }
            if rh.contains(midiNote) { return rhColor }
            if lh.contains(midiNote) { return lhColor }
            return .blue
        }()

        switch (isDetected, isTouched) {
        case (true, true): return .cyan
        case (true, false): return detectedColor
        case (false, true): return .green
        case (false, false):
            return isExpected ? .orange : nil
        }
    }

    /// Letter shown on a highlighted key when
    /// `accessibilityDifferentiateWithoutColor` is enabled.
    ///
    /// R = right hand, L = left hand, `•` = both/chord. Returns nil when the
    /// key has no RH/LH/chord membership (detection-only, touch-only, and
    /// expected-note highlights are color-only and don't need differentiation).
    ///
    /// - Parameter midiNote: MIDI note number to classify.
    /// - Returns: "R", "L", "•", or nil.
    private func differentiateLetter(forMidi midiNote: Int) -> String? {
        let rh = highlightState?.rhNotes ?? []
        let lh = highlightState?.lhNotes ?? []
        let chord = highlightState?.chordNotes ?? []
        if chord.contains(midiNote) { return "•" }
        if rh.contains(midiNote) && lh.contains(midiNote) { return "•" }
        if rh.contains(midiNote) { return "R" }
        if lh.contains(midiNote) { return "L" }
        return nil
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
