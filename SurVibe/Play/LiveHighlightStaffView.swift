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
    let activeMidiNotes: Set<UInt8>
    let saPitch: UInt8
    let notationMode: PlayTabNotationMode

    var body: some View {
        VStack(spacing: 8) {
            if notationMode == .western || notationMode == .both {
                StaffNotationRenderer(
                    notes: [],
                    currentNoteIndex: nil,
                    keySignature: .cMajor,
                    timeSignature: .fourFour,
                    zoomScale: 1.0,
                    detectedMidiNote: nil,
                    detectedMidiNotes: Set(activeMidiNotes.map(Int.init)),
                    currentNoteMatchState: nil
                )
            }
            if notationMode == .sargam || notationMode == .both {
                sargamRow
            }
        }
        .accessibilityHidden(true)  // keyboard provides VoiceOver reach
    }

    /// One-line strip of Sargam syllables for currently-pressed notes.
    private var sargamRow: some View {
        HStack(spacing: 12) {
            ForEach(Array(activeMidiNotes).sorted(), id: \.self) { midi in
                Text(SargamLabeler.label(midi: midi, saPitch: saPitch).display)
                    .font(.title2)
                    .monospaced()
            }
            if activeMidiNotes.isEmpty {
                Text(" ").font(.title2)  // placeholder to preserve height
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }
}

#Preview("No notes") {
    LiveHighlightStaffView(activeMidiNotes: [], saPitch: 60, notationMode: .both)
        .frame(height: 200)
        .padding()
}

#Preview("C major triad, Sa = C") {
    LiveHighlightStaffView(activeMidiNotes: [60, 64, 67], saPitch: 60, notationMode: .both)
        .frame(height: 200)
        .padding()
}

#Preview("Sargam-only, Sa = D") {
    LiveHighlightStaffView(activeMidiNotes: [62, 64, 66], saPitch: 62, notationMode: .sargam)
        .frame(height: 200)
        .padding()
}
