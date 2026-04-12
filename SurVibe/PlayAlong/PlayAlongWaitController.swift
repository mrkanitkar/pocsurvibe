import Foundation
import os
import SVCore
import SVLearning

/// Controls wait-mode behavior for play-along, pausing playback at each note
/// until the user plays the correct note.
///
/// Wraps `WaitModeEngine` with playback-aware logic: tracks which note
/// the user needs to play next and evaluates attempts using the
/// full Swar name (e.g., "Komal Re", not "Re").
///
/// ## Full Swar Name Contract
/// All note comparisons use the full swar name including modifiers
/// (e.g., "Komal Re", "Tivra Ma") to prevent false matches between
/// "Re" and "Komal Re". This matches the `NoteEvent.swarName` format.
@Observable
@MainActor
final class PlayAlongWaitController {
    // MARK: - Logger

    private static let logger = Logger.survibe(category: "PlayAlongWait")

    // MARK: - Properties

    /// The note events for the current song.
    private let noteEvents: [NoteEvent]

    /// Underlying wait mode engine from SVLearning.
    private let waitEngine: WaitModeEngine

    /// Index of the note the user is expected to play.
    private(set) var currentNoteIndex: Int = 0

    /// Whether the controller is actively waiting for the user to play a note.
    private(set) var isWaitingForNote: Bool = false

    // MARK: - Initialization

    /// Create a wait controller for the given sequence of note events.
    ///
    /// - Parameters:
    ///   - noteEvents: The ordered note events from the loaded song.
    ///   - waitEngine: Wait mode engine to delegate evaluation to.
    ///     If `nil`, a new instance with default configuration is created.
    init(
        noteEvents: [NoteEvent],
        waitEngine: WaitModeEngine? = nil
    ) {
        self.noteEvents = noteEvents
        self.waitEngine = waitEngine ?? WaitModeEngine()
    }

    // MARK: - Public Methods

    /// Set the current note index and begin waiting for the user to play it.
    ///
    /// Transitions `isWaitingForNote` to `true` and tells the underlying
    /// wait engine to start its patience timer.
    ///
    /// - Parameter index: Index into `noteEvents` for the expected note.
    func setCurrentNoteIndex(_ index: Int) {
        currentNoteIndex = index
        isWaitingForNote = true
        waitEngine.waitForNote()
        Self.logger.debug("Waiting for note at index \(index, privacy: .public)")
    }

    /// Evaluate a detected note name against the expected note.
    ///
    /// Uses `noteEvent.swarName` (the full name like "Komal Re") for
    /// comparison to prevent false positives between base notes and
    /// their Komal/Tivra variants.
    ///
    /// - Parameter detectedNoteName: The full swar name of the detected note
    ///   (e.g., "Sa", "Komal Re", "Tivra Ma").
    /// - Returns: `true` if the detected note matches the expected note.
    func evaluateAttempt(detectedNoteName: String) -> Bool {
        guard currentNoteIndex < noteEvents.count else { return false }
        let expected = noteEvents[currentNoteIndex]

        let result = waitEngine.evaluateAttempt(
            detectedNoteName: detectedNoteName,
            detectedOctave: expected.octave,
            detectedCents: 0,
            expectedNoteName: expected.swarName,
            expectedOctave: expected.octave
        )

        let exp = expected.swarName
        Self.logger.debug(
            "Attempt: \(detectedNoteName, privacy: .public) vs \(exp, privacy: .public) = \(result, privacy: .public)"
        )
        if result {
            isWaitingForNote = false
        }
        return result
    }

    /// Reset the controller for a new session.
    ///
    /// Clears the current note index and waiting state, and resets
    /// the underlying wait engine's statistics.
    func reset() {
        currentNoteIndex = 0
        isWaitingForNote = false
        waitEngine.reset()
        Self.logger.info("PlayAlong wait controller reset")
    }
}
