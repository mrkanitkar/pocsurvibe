// SurVibe/Play/LiveHighlightStaffView.swift
import SVCore
import SVLearning
import SwiftUI

/// MIDI cutoff that splits notes between the treble and bass staves.
///
/// Middle C (MIDI 60) and above render on the treble staff; everything
/// below renders on the bass staff. This matches the standard piano
/// grand-staff convention and keeps low octaves out of the treble staff
/// where they would clip with many ledger lines.
private let grandStaffSplitMidi: Int = 60

/// Live grand-staff view that highlights currently-pressed MIDI notes
/// across treble and bass clefs.
///
/// Used as the top half of the Play tab. The staves themselves show
/// recorded notes from the strip; key heads also light up as the user plays.
/// When `notationMode` is `.sargam` or `.both`, a single-row Sargam strip
/// renders the current note(s) as Sargam syllables relative to `saPitch`.
struct LiveHighlightStaffView: View {
    /// Isolated observable that owns the currently-highlighted MIDI note set.
    ///
    /// Reading `highlightState.activeMidiNotes` inside `body` registers a
    /// SwiftUI dependency on JUST this property; updates re-render this
    /// view (and its child renderers) without invalidating `PlayTab.body`.
    /// This mirrors PlayAlong's `HighlightState`-scoped re-render path.
    let highlightState: PlayTabHighlightState
    let saPitch: UInt8
    let notationMode: PlayTabNotationMode

    /// MIDI notes currently highlighted (touch + MIDI). Read once per body.
    private var activeMidiNotes: Set<Int> { highlightState.activeMidiNotes }

    /// Empty score for the live staff — scratchpad rendering moves to the
    /// bottom strip / expanded sheet (Task 11+). Live staff just lights up
    /// pressed key heads.
    private let trebleNotes: [WesternNote] = []
    private let bassNotes: [WesternNote] = []

    /// Currently-held notes routed to the treble staff for live highlight.
    private var trebleHighlight: Set<Int> {
        activeMidiNotes.filter { $0 >= grandStaffSplitMidi }
    }

    /// Currently-held notes routed to the bass staff for live highlight.
    private var bassHighlight: Set<Int> {
        activeMidiNotes.filter { $0 < grandStaffSplitMidi }
    }

    var body: some View {
        VStack(spacing: 4) {
            if notationMode == .western || notationMode == .both {
                StaffNotationRenderer(
                    notes: trebleNotes,
                    currentNoteIndex: nil,
                    keySignature: .cMajor,
                    timeSignature: .fourFour,
                    zoomScale: 1.0,
                    detectedMidiNote: nil,
                    detectedMidiNotes: trebleHighlight,
                    currentNoteMatchState: nil,
                    clef: .treble
                )
                .accessibilityHidden(true)
                StaffNotationRenderer(
                    notes: bassNotes,
                    currentNoteIndex: nil,
                    keySignature: .cMajor,
                    timeSignature: .fourFour,
                    zoomScale: 1.0,
                    detectedMidiNote: nil,
                    detectedMidiNotes: bassHighlight,
                    currentNoteMatchState: nil,
                    clef: .bass
                )
                // Staff is decorative for VoiceOver — the keyboard
                // already announces individual notes.
                .accessibilityHidden(true)
            }
            if notationMode == .sargam || notationMode == .both {
                sargamRow
            }
        }
    }

    /// One-line strip of Sargam syllables for currently-pressed notes.
    ///
    /// Exposed to VoiceOver as the only place chord syllables are accessible
    /// while held — the staff renderer is hidden, and the keyboard surfaces
    /// individual note names but not the Sargam labels.
    private var sargamRow: some View {
        HStack(spacing: 12) {
            ForEach(Array(activeMidiNotes).sorted(), id: \.self) { midi in
                Text(SargamLabeler.label(midi: UInt8(midi), saPitch: saPitch).display)
                    .font(.title2)
                    .monospaced()
            }
            if activeMidiNotes.isEmpty {
                Text(" ").font(.title2)  // placeholder to preserve height
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sargamAccessibilityLabel)
    }

    /// Comma-joined Sargam syllables for currently-pressed notes — read aloud
    /// by VoiceOver. Empty active set yields "No notes".
    private var sargamAccessibilityLabel: String {
        if activeMidiNotes.isEmpty {
            return String(localized: "No notes")
        }
        let syllables = Array(activeMidiNotes)
            .sorted()
            .map { SargamLabeler.label(midi: UInt8($0), saPitch: saPitch).display }
            .joined(separator: ", ")
        return String(localized: "Currently playing: \(syllables)")
    }
}

/// Build a `PlayTabHighlightState` seeded with the given notes for previews.
@MainActor
private func previewHighlight(_ notes: Set<Int>) -> PlayTabHighlightState {
    let hs = PlayTabHighlightState()
    hs.activeMidiNotes = notes
    return hs
}

#Preview("No notes") {
    LiveHighlightStaffView(
        highlightState: previewHighlight([]),
        saPitch: 60,
        notationMode: .both
    )
    .frame(height: 200)
    .padding()
}

#Preview("C major triad, Sa = C") {
    LiveHighlightStaffView(
        highlightState: previewHighlight([60, 64, 67]),
        saPitch: 60,
        notationMode: .both
    )
    .frame(height: 200)
    .padding()
}

#Preview("Sargam-only, Sa = D") {
    LiveHighlightStaffView(
        highlightState: previewHighlight([62, 64, 66]),
        saPitch: 62,
        notationMode: .sargam
    )
    .frame(height: 200)
    .padding()
}

#Preview("Bass + Treble chord (G2, C4, G4)") {
    LiveHighlightStaffView(
        highlightState: previewHighlight([43, 60, 67]),
        saPitch: 60,
        notationMode: .both
    )
    .frame(height: 320)
    .padding()
}

/// Both clefs across the full piano range — verifies clef-aware position math.
#Preview("Both clefs — full piano range") {
    let midis: Set<Int> = [36, 43, 50, 57, 60, 64, 71, 77, 96]
    return LiveHighlightStaffView(
        highlightState: previewHighlight(midis),
        saPitch: 60,
        notationMode: .western
    )
    .frame(height: 480)
    .padding()
}
