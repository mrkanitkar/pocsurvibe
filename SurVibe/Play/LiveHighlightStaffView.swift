// SurVibe/Play/LiveHighlightStaffView.swift
import SVLearning
import SwiftUI

/// Static grand-staff view that highlights currently-pressed MIDI notes.
///
/// Used as the top half of the Play tab. The staff itself shows no notation;
/// instead, key heads light up as the user plays. When `notationMode` is
/// `.sargam` or `.both`, a single-row Sargam strip renders the current note(s)
/// as Sargam syllables relative to `saPitch`.
struct LiveHighlightStaffView: View {
    /// MIDI notes currently highlighted, sourced from the display-link-driven
    /// `MIDINoteHighlightCoordinator` so the visual updates are bounded by
    /// the display refresh rate (~8–16 ms) rather than the MIDI bookkeeping
    /// `Task { @MainActor }` hop.
    let activeMidiNotes: Set<Int>
    let saPitch: UInt8
    let notationMode: PlayTabNotationMode
    let recordedNotes: [RecordedNote]

    /// Played notes mapped into the renderer's note model. Quarter-note
    /// duration is used for everything because we don't track real timing —
    /// SurVibe's recording strip is a sequence, not a tempo-aware capture.
    @MainActor
    private var westernNotes: [WesternNote] {
        recordedNotes.map(Self.westernNote(from:))
    }

    var body: some View {
        VStack(spacing: 8) {
            if notationMode == .western || notationMode == .both {
                StaffNotationRenderer(
                    notes: westernNotes,
                    currentNoteIndex: nil,
                    keySignature: .cMajor,
                    timeSignature: .fourFour,
                    zoomScale: 1.0,
                    detectedMidiNote: nil,
                    detectedMidiNotes: activeMidiNotes,
                    currentNoteMatchState: nil
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

    /// Convert a `RecordedNote` into the renderer's `WesternNote` shape.
    /// Uses `WesternNoteHelper` for the note-name + octave calculation and
    /// hard-codes a quarter-note duration (the strip has no real timing).
    private static func westernNote(from recorded: RecordedNote) -> WesternNote {
        let midi = Int(recorded.midi)
        return WesternNote(
            note: WesternNoteHelper.displayName(from: midi),
            duration: 1.0,
            midiNumber: midi
        )
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

#Preview("No notes") {
    LiveHighlightStaffView(
        activeMidiNotes: [],
        saPitch: 60,
        notationMode: .both,
        recordedNotes: []
    )
    .frame(height: 200)
    .padding()
}

#Preview("C major triad, Sa = C") {
    LiveHighlightStaffView(
        activeMidiNotes: [60, 64, 67] as Set<Int>,
        saPitch: 60,
        notationMode: .both,
        recordedNotes: [
            RecordedNote(midi: 60),
            RecordedNote(midi: 64),
            RecordedNote(midi: 67),
        ]
    )
    .frame(height: 200)
    .padding()
}

#Preview("Sargam-only, Sa = D") {
    LiveHighlightStaffView(
        activeMidiNotes: [62, 64, 66] as Set<Int>,
        saPitch: 62,
        notationMode: .sargam,
        recordedNotes: []
    )
    .frame(height: 200)
    .padding()
}
