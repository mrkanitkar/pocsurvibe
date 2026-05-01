import Foundation
import SVAudio
import SVCore
import os

private let notationGenLogger = Logger.survibe(category: "SongNotationGen")

/// Generates Sargam + Western notation JSON arrays from a song's raw MIDI
/// data. Used to populate `Song.sargamNotation` / `Song.westernNotation`
/// for MXL-imported songs that ship `midiData` but no notation blobs.
///
/// The Drop-style notation views (`ScrollingSheetView`) read those JSON
/// blobs directly. Without this generator they show an empty staff for
/// every MXL import, including the seeded Sukhkarta and James Bond rows.
///
/// The generator pipes `midiData` through the existing render pipeline:
///
/// ```
/// midiData
///   → VerovioBridge.summarizeSMF      (track info)
///   → PartSplitter().split             (learner.notes : [ExpectedNote])
///   → ExpectedNote → SargamNote / WesternNote
/// ```
///
/// Durations are emitted in *quarter-note beats* to match the existing
/// JSON format consumed by `SongDetailView` / `ScrollingSheetView`.
@MainActor
enum SongNotationGenerator {

    /// Convert raw SMF bytes into the two notation JSON blobs.
    ///
    /// - Parameter midiData: SMF bytes (typically `Song.midiData`).
    /// - Returns: A tuple of optional Data blobs. Either may be `nil` when
    ///   the input fails to parse or contains no playable learner notes.
    static func generateNotationJSON(from midiData: Data)
        -> (sargam: Data?, western: Data?)
    {
        guard !midiData.isEmpty else { return (nil, nil) }
        let rendered: RenderedMIDI
        do {
            rendered = try VerovioBridge.summarizeSMF(midiData)
        } catch {
            notationGenLogger.warning("summarizeSMF failed: \(error.localizedDescription, privacy: .public)")
            return (nil, nil)
        }
        let split: PartSplit
        do {
            split = try PartSplitter().split(rendered)
        } catch {
            notationGenLogger.warning("PartSplitter failed: \(error.localizedDescription, privacy: .public)")
            return (nil, nil)
        }
        let learnerNotes = split.learner.notes
        guard !learnerNotes.isEmpty else { return (nil, nil) }
        let sargamArray = learnerNotes.map(makeSargamNote(from:))
        let westernArray = learnerNotes.map(makeWesternNote(from:))
        let encoder = JSONEncoder()
        let sargamData = try? encoder.encode(sargamArray)
        let westernData = try? encoder.encode(westernArray)
        return (sargamData, westernData)
    }

    /// Map an `ExpectedNote` to a `SargamNote`. Splits compound swar names
    /// like `"Komal Re"` into `note: "Re"` + `modifier: "Komal"`.
    private static func makeSargamNote(from note: ExpectedNote) -> SargamNote {
        let info = noteNameInfo(for: note.midiNote)
        let parts = info.swarName.split(separator: " ", maxSplits: 1)
        let baseNote: String
        let modifier: String?
        if parts.count == 2 {
            modifier = String(parts[0]).lowercased()
            baseNote = String(parts[1])
        } else {
            modifier = nil
            baseNote = info.swarName
        }
        return SargamNote(
            note: baseNote,
            octave: info.octave,
            duration: note.durationBeats,
            modifier: modifier
        )
    }

    /// Map an `ExpectedNote` to a `WesternNote`.
    private static func makeWesternNote(from note: ExpectedNote) -> WesternNote {
        let info = noteNameInfo(for: note.midiNote)
        return WesternNote(
            note: info.westernName,
            duration: note.durationBeats,
            midiNumber: Int(note.midiNote)
        )
    }

    /// MIDI → (swarName, westernName, octave). Mirrors the private helper
    /// inside `NoteEvent` so this generator is independent of NoteEvent's
    /// internal API surface.
    private static func noteNameInfo(for midiNote: UInt8)
        -> (swarName: String, westernName: String, octave: Int)
    {
        let noteNumber = Int(midiNote)
        let octave = (noteNumber / 12) - 1
        let semitone = noteNumber % 12

        // Sargam — matches `Swar.midiOffset`.
        let swarNames = [
            "Sa", "Komal Re", "Re", "Komal Ga", "Ga",
            "Ma", "Tivra Ma", "Pa", "Komal Dha", "Dha",
            "Komal Ni", "Ni"
        ]
        // Western
        let westernNames = [
            "C", "Db", "D", "Eb", "E", "F",
            "F#", "G", "Ab", "A", "Bb", "B"
        ]
        return (
            swarName: swarNames[semitone],
            westernName: "\(westernNames[semitone])\(octave)",
            octave: octave
        )
    }
}
