import Foundation
import os.log

/// State of the Wait Mode note-by-note engine.
///
/// Transitions: idle -> waiting -> (advancing | skipped) -> waiting -> ...
public enum WaitModeState: Equatable, Sendable {
    /// Engine is not actively waiting (between notes or not started).
    case idle
    /// Waiting for the student to play the expected note.
    case waiting
    /// Student played correctly; advancing to the next note.
    case advancing
    /// Patience timer expired; auto-skipped to the next note.
    case skipped
}

/// Wait Mode state machine that pauses at each note until the student plays correctly.
///
/// When enabled, the practice session pauses at each note and waits for the
/// student to match the expected pitch. If the student doesn't respond within
/// the patience timeout, the note is auto-skipped.
///
/// ## State Flow
/// ```
/// idle -> waitForNote() -> waiting -> evaluateAttempt() -> advancing -> waitForNote() -> ...
///                                  -> [patience timeout] -> skipped -> waitForNote() -> ...
/// ```
@Observable
@MainActor
public final class WaitModeEngine {
    // MARK: - Public Properties

    /// Current state of the wait mode engine.
    public private(set) var state: WaitModeState = .idle

    /// Configuration controlling wait behavior.
    public var configuration: WaitModeConfiguration

    /// Number of notes the student got correct on the first attempt.
    public private(set) var correctOnFirstAttempt: Int = 0

    /// Number of notes that were auto-skipped due to patience timeout.
    public private(set) var skippedCount: Int = 0

    /// Total number of attempts across all notes.
    public private(set) var totalAttempts: Int = 0

    // MARK: - Private Properties

    /// Task managing the patience timer countdown.
    private var patienceTask: Task<Void, Never>?

    /// Whether the current note has had any incorrect attempts.
    private var hasIncorrectAttemptForCurrentNote: Bool = false

    private static let logger = Logger.survibe(category: "WaitModeEngine")

    // MARK: - Initialization

    /// Create a Wait Mode engine with the given configuration.
    ///
    /// - Parameter configuration: Wait mode settings. Defaults to disabled.
    public init(configuration: WaitModeConfiguration = WaitModeConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Public Methods

    /// Begin waiting for the student to play the expected note.
    ///
    /// Transitions to `.waiting` state and starts the patience timer
    /// if configured. Call this when advancing to a new note in the sequence.
    public func waitForNote() {
        state = .waiting
        hasIncorrectAttemptForCurrentNote = false
        startPatienceTimer()
        Self.logger.info("Waiting for note")
    }

    /// Evaluate a student's pitch attempt against the expected note.
    ///
    /// Compares the detected note name and optionally cents offset against
    /// the expected note based on the configured criteria.
    ///
    /// - Parameters:
    ///   - detectedNoteName: The note name detected from pitch analysis.
    ///   - detectedOctave: The octave of the detected note.
    ///   - detectedCents: Cents offset from the nearest note.
    ///   - expectedNoteName: The expected swar note name.
    ///   - expectedOctave: The expected octave.
    /// - Returns: `true` if the attempt matches the criteria, `false` otherwise.
    @discardableResult
    public func evaluateAttempt(
        detectedNoteName: String,
        detectedOctave: Int,
        detectedCents: Double,
        expectedNoteName: String,
        expectedOctave: Int
    ) -> Bool {
        guard state == .waiting else { return false }

        totalAttempts += 1

        let isCorrect: Bool
        switch configuration.waitCriteria {
        case .correctPitch:
            isCorrect = detectedNoteName == expectedNoteName && detectedOctave == expectedOctave

        case .withinTolerance:
            let noteMatches = detectedNoteName == expectedNoteName && detectedOctave == expectedOctave
            let withinTolerance = abs(detectedCents) <= configuration.pitchToleranceCents
            isCorrect = noteMatches && withinTolerance

        case .pitchAndDuration:
            // For now, treat same as correctPitch. Duration check
            // will be added when we track note hold time.
            isCorrect = detectedNoteName == expectedNoteName && detectedOctave == expectedOctave
        }

        if isCorrect {
            if !hasIncorrectAttemptForCurrentNote {
                correctOnFirstAttempt += 1
            }
            cancelPatienceTimer()
            state = .advancing
            Self.logger.info("Correct attempt — advancing")
        } else {
            hasIncorrectAttemptForCurrentNote = true
        }

        return isCorrect
    }

    /// Manually skip the current note without waiting for the patience timer.
    public func skipCurrentNote() {
        guard state == .waiting else { return }
        cancelPatienceTimer()
        skippedCount += 1
        state = .skipped
        Self.logger.info("Note manually skipped")
    }

    /// Reset the engine state for a new practice session.
    public func reset() {
        cancelPatienceTimer()
        state = .idle
        correctOnFirstAttempt = 0
        skippedCount = 0
        totalAttempts = 0
        hasIncorrectAttemptForCurrentNote = false
    }

    // MARK: - Private Methods

    /// Start the patience countdown timer.
    ///
    /// If `patienceSeconds` is 0, no timer is started (unlimited patience).
    /// When the timer expires, the note is auto-skipped.
    private func startPatienceTimer() {
        cancelPatienceTimer()

        let patience = configuration.patienceSeconds
        guard patience > 0 else { return }

        patienceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(patience))
            guard !Task.isCancelled else { return }
            guard let self, self.state == .waiting else { return }
            self.skippedCount += 1
            self.state = .skipped
            Self.logger.info("Patience timer expired — note skipped")
        }
    }

    /// Cancel any running patience timer.
    private func cancelPatienceTimer() {
        patienceTask?.cancel()
        patienceTask = nil
    }
}
