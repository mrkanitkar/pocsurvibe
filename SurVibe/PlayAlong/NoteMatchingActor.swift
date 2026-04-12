import Foundation
import SVCore
import SVAudio
import SVLearning
import os.log

/// Off-main-actor engine that evaluates a MIDI or microphone note input against the
/// currently expected note event and returns a `ScoringDiff`.
///
/// ## Why an Actor
/// `processNoteInput` in `PlayAlongViewModel` ran on `@MainActor`, competing with
/// SwiftUI's render passes for falling notes and piano key highlights. At 200 BPM
/// with 16th notes, MIDI events arrive every ~75 ms — faster than SwiftUI can render
/// and score simultaneously on one actor. Moving all scoring arithmetic here lets
/// `@MainActor` focus on UI work; the scoring result is a tiny `ScoringDiff` that
/// hops back to update `@Observable` state.
///
/// ## Thread Safety
/// All inputs to `evaluate` are `Sendable` value types (structs, enums, primitives).
/// No shared mutable state is accessed; the actor serializes concurrent calls so
/// back-to-back rapid keypresses are evaluated in order without races.
///
/// ## Wait Mode
/// `PlayAlongWaitController` is `@MainActor`-isolated and cannot be passed here.
/// Instead, the caller evaluates the wait-mode match on `@MainActor` first and
/// passes the result as `waitModeMatch: Bool?` (nil = wait mode disabled).
actor NoteMatchingActor {

    // MARK: - Private Helpers

    private static let logger = Logger.survibe(category: "NoteMatching")

    // MARK: - Public Interface

    /// Evaluate a note input against the expected event and return a scoring diff.
    ///
    /// All parameters are `Sendable` value types — no actor hop required to pass them.
    /// The returned `ScoringDiff` is consumed on `@MainActor` to update `noteStates`,
    /// `noteScores`, and `accuracy`.
    ///
    /// - Parameters:
    ///   - midiNote: MIDI note number of the input (0–127).
    ///   - expectedEvent: The note event currently under evaluation.
    ///   - currentPitch: Latest pitch detection result for cents deviation, or `nil`.
    ///   - ragaScoringContext: Raga-aware scoring context, or `nil` for 12ET.
    ///   - waitModeMatch: `true` if wait mode matched, `false` if wait mode active but
    ///     no match, `nil` if wait mode is disabled (standard scoring applies).
    /// - Returns: A `ScoringDiff` describing the state and score delta.
    func evaluate(
        midiNote: Int,
        expectedEvent: NoteEvent,
        currentPitch: PitchResult?,
        ragaScoringContext: RagaScoringContext?,
        waitModeMatch: Bool?
    ) -> ScoringDiff {
        let detectedSwarName = Self.swarNameFromMIDI(UInt8(clamping: midiNote))
        let isCorrectMIDI = Int(expectedEvent.midiNote) == midiNote

        let centsDeviation: Double
        if let pitch = currentPitch {
            centsDeviation = abs(pitch.ragaCentsOffset ?? pitch.centsOffset)
        } else {
            centsDeviation = isCorrectMIDI ? 0 : 50
        }

        // Wait mode path: caller has already evaluated the match on @MainActor.
        if let matched = waitModeMatch {
            if matched {
                let score = NoteScoreCalculator.score(
                    expectedNote: expectedEvent.swarName,
                    detectedNote: detectedSwarName,
                    pitchDeviationCents: centsDeviation,
                    timingDeviationSeconds: 0,
                    durationDeviation: 0,
                    ragaPitchDeviationCents: currentPitch?.ragaCentsOffset.map { abs($0) },
                    ragaContext: ragaScoringContext
                )
                return ScoringDiff(
                    noteEventID: expectedEvent.id,
                    newState: .correct,
                    score: score,
                    streakOutcome: .hit(grade: score.grade)
                )
            } else {
                return ScoringDiff(
                    noteEventID: expectedEvent.id,
                    newState: .wrong,
                    score: nil,
                    streakOutcome: .noChange
                )
            }
        }

        // Standard mode: immediate scoring based on MIDI correctness.
        if isCorrectMIDI {
            let score = NoteScoreCalculator.score(
                expectedNote: expectedEvent.swarName,
                detectedNote: detectedSwarName,
                pitchDeviationCents: centsDeviation,
                timingDeviationSeconds: 0,
                durationDeviation: 0,
                ragaPitchDeviationCents: currentPitch?.ragaCentsOffset.map { abs($0) },
                ragaContext: ragaScoringContext
            )
            return ScoringDiff(
                noteEventID: expectedEvent.id,
                newState: .correct,
                score: score,
                streakOutcome: .hit(grade: score.grade)
            )
        } else {
            let score = NoteScoreCalculator.score(
                expectedNote: expectedEvent.swarName,
                detectedNote: detectedSwarName,
                pitchDeviationCents: 50,
                timingDeviationSeconds: 0,
                durationDeviation: 0
            )
            return ScoringDiff(
                noteEventID: expectedEvent.id,
                newState: .wrong,
                score: score,
                streakOutcome: .miss
            )
        }
    }

    // MARK: - Private Helpers

    /// Derive the full swar name from a MIDI note number.
    ///
    /// - Parameter midiNote: MIDI note number (0–127).
    /// - Returns: Full swar name, e.g. "Komal Re", "Tivra Ma", "Sa".
    private static func swarNameFromMIDI(_ midiNote: UInt8) -> String {
        let semitone = Int(midiNote) % 12
        let swar = Swar.allCases.first { $0.midiOffset == semitone } ?? .sa
        return swar.rawValue
    }
}
