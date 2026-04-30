import Foundation
import SVAudio
import SVCore

// MARK: - Spec §5.1 Types

/// Timing classification for a single note attempt.
///
/// Real-time windows (wall-clock seconds, **not** beats — they don't contract
/// when the user practises at slower tempi):
/// - `.perfect`: |Δ| < 60 ms
/// - `.good`:    60 ms ≤ Δ < 150 ms (late side)
/// - `.early`:   60 ms ≤ -Δ < 150 ms or 150 ms ≤ -Δ < 300 ms
/// - `.late`:    150 ms ≤ Δ < 300 ms (late side)
/// - `.miss`:    |Δ| ≥ 300 ms
public enum TimingClass: String, Sendable, Hashable {
    case perfect
    case good
    case late
    case early
    case miss
}

/// Result of scoring a single MIDI note-on against an expected note.
public struct NoteVerdict: Sendable {
    /// Identity of the expected note that was matched.
    public let expectedID: UUID

    /// Per-note score from `NoteScoreCalculator`.
    public let score: NoteScore

    /// Coarse timing window the attempt landed in.
    public let timing: TimingClass

    /// Signed real-time delta in seconds (positive = late, negative = early).
    public let timingDeltaSeconds: Double

    /// Create a verdict.
    public init(
        expectedID: UUID,
        score: NoteScore,
        timing: TimingClass,
        timingDeltaSeconds: Double
    ) {
        self.expectedID = expectedID
        self.score = score
        self.timing = timing
        self.timingDeltaSeconds = timingDeltaSeconds
    }
}

/// Aggregate session-level result for a play-along run.
///
/// Surfaces two distinct headline metrics — `notesCorrectPercent` and
/// `timingAccuracyPercent` — instead of a single conflated number, per spec
/// §5.1 results-overlay design ("right key" and "right time" are different
/// skills). The aggregate `composite` `NoteScore` is shown smaller below.
public struct SessionScoreSummary: Sendable {
    /// Total expected notes the user attempted to play (matched + extras).
    public let notesAttempted: Int

    /// Notes where the user pressed the right key in any timing window.
    public let notesCorrect: Int

    /// Expected notes whose window passed without input.
    public let notesMissed: Int

    /// User key-presses that did not align with any expected window.
    public let notesExtra: Int

    /// 100 × mean(perfect=1.0, good=0.7, late/early=0.4, miss=0.0) over verdicts.
    public let timingAccuracyPercent: Double

    /// 100 × notesCorrect / max(1, totalExpectedNotes).
    public let notesCorrectPercent: Double

    /// Aggregated `NoteScore` across all verdicts (mean of `accuracy`).
    public let composite: NoteScore

    /// Create a session summary.
    public init(
        notesAttempted: Int,
        notesCorrect: Int,
        notesMissed: Int,
        notesExtra: Int,
        timingAccuracyPercent: Double,
        notesCorrectPercent: Double,
        composite: NoteScore
    ) {
        self.notesAttempted = notesAttempted
        self.notesCorrect = notesCorrect
        self.notesMissed = notesMissed
        self.notesExtra = notesExtra
        self.timingAccuracyPercent = timingAccuracyPercent
        self.notesCorrectPercent = notesCorrectPercent
        self.composite = composite
    }
}

// MARK: - ScoringAdapter

/// Bridges live MIDI input to the existing `NoteScoreCalculator` for play-along
/// scoring against a `LearnerScore`.
///
/// Timing windows are real-time (wall-clock seconds) so they don't contract
/// when the learner practises at slower tempi. Host-time deltas are converted
/// to beats with the formula:
///
///     currentBeat = elapsedSec * (originalBPM / 60) * tempoScale
///
/// and inverted via:
///
///     secDelta = beatDelta * (60 / originalBPM) / tempoScale
///
/// Pitch is exact for MIDI input. The adapter computes
/// `pitchDeviationCents = |playedMIDI - expectedMIDI| * 100`, so a wrong key
/// drives the composite score down via `NoteScoreCalculator`'s pitch term —
/// matching the user expectation that "right key" is binary on a piano.
@MainActor
public final class ScoringAdapter {

    // MARK: Stored State

    /// The expected-note timeline.
    private let score: LearnerScore

    /// MIDI note number that maps to "Sa" for swar-string conversion.
    /// Defaults to C4 (60); configurable via tanpura settings in the app.
    private let tonicSaPitch: UInt8

    /// IDs of expected notes that have already been consumed (matched or swept).
    private var consumed: Set<UUID> = []

    /// Verdicts produced so far, keyed by expected-note ID.
    private var verdicts: [UUID: NoteVerdict] = [:]

    /// Count of user key-presses that did not match any expected window.
    private var extras: Int = 0

    // MARK: Initialization

    /// Create a `ScoringAdapter`.
    /// - Parameters:
    ///   - score: The learner part to score against.
    ///   - tonicSaPitch: MIDI note number that maps to Sa. Default 60 (C4).
    public init(score: LearnerScore, tonicSaPitch: UInt8 = 60) {
        self.score = score
        self.tonicSaPitch = tonicSaPitch
    }

    // MARK: Public API

    /// Feed a MIDI note-on with host-tick timestamp and produce a verdict.
    ///
    /// The `hostTime` should be captured at the CoreMIDI callback site, *before*
    /// any `MainActor` hop, to preserve sub-millisecond timing fidelity.
    ///
    /// Behavior:
    /// - Finds the unconsumed expected note whose onset is closest to the
    ///   converted current beat.
    /// - If no such candidate exists, increments the `extras` counter and
    ///   returns `nil`.
    /// - If the candidate's timing window is `.miss`, returns `nil` and does
    ///   not consume the note (it will be swept later).
    /// - Otherwise, consumes the candidate, computes a `NoteScore` with
    ///   pitch deviation derived from |playedMIDI - expectedMIDI| × 100 cents,
    ///   and returns a `NoteVerdict`.
    ///
    /// - Parameters:
    ///   - midiNote: MIDI note number played by the user (0–127).
    ///   - velocity: MIDI velocity (0–127). Currently unused for scoring.
    ///   - hostTime: Host-clock timestamp captured at the input event.
    ///   - sequencerStartHostTime: Host-clock timestamp at sequencer start.
    ///   - currentTempoScale: Sequencer tempo scale (0.5...1.5).
    /// - Returns: A `NoteVerdict` if the press matched an expected window,
    ///            otherwise `nil`.
    public func ingest(
        midiNote: UInt8,
        velocity: UInt8,
        hostTime: HostTime,
        sequencerStartHostTime: HostTime,
        currentTempoScale: Float
    ) -> NoteVerdict? {
        _ = velocity  // reserved for v2 dynamics scoring on MIDI input
        let elapsedSec = hostTime.seconds(since: sequencerStartHostTime)
        let tempoScale = max(0.0001, Double(currentTempoScale))
        let currentBeat = elapsedSec * (score.originalBPM / 60.0) * tempoScale

        guard let candidate = nearestUnconsumed(toBeat: currentBeat) else {
            extras += 1
            return nil
        }

        let beatDelta = currentBeat - candidate.beat
        let secDelta = beatDelta * (60.0 / score.originalBPM) / tempoScale
        let timingClass = classify(secDelta: secDelta)

        guard timingClass != .miss else {
            // Don't consume: a future, better-aligned press might still match,
            // or the note will eventually be swept by `sweepMissed`.
            return nil
        }

        // For MIDI input, derive pitch deviation in cents from the semitone
        // distance to the expected note. Right key → 0 cents → pitchAccuracy 1.0.
        let pitchDevCents = Double(abs(Int(midiNote) - Int(candidate.midiNote))) * 100.0
        let expectedSwar = swarString(forMIDI: candidate.midiNote, tonicSa: tonicSaPitch)
        let detectedSwar = swarString(forMIDI: midiNote, tonicSa: tonicSaPitch)

        let noteScore = NoteScoreCalculator.score(
            expectedNote: expectedSwar,
            detectedNote: detectedSwar,
            pitchDeviationCents: pitchDevCents,
            timingDeviationSeconds: abs(secDelta),
            durationDeviation: 0,
            ragaContext: nil
        )

        consumed.insert(candidate.id)
        let verdict = NoteVerdict(
            expectedID: candidate.id,
            score: noteScore,
            timing: timingClass,
            timingDeltaSeconds: secDelta
        )
        verdicts[candidate.id] = verdict
        return verdict
    }

    /// Find the next unconsumed expected note strictly after `beat`.
    /// - Parameter beat: Current beat position (original-tempo beats).
    /// - Returns: The next expected note, or `nil` if all later notes are consumed.
    public func nextExpected(afterBeat beat: Double) -> ExpectedNote? {
        score.notes.first { $0.beat > beat && !consumed.contains($0.id) }
    }

    /// Sweep expected notes whose late-window has fully passed without input,
    /// marking them consumed and returning their IDs as "missed".
    ///
    /// The late-window threshold is 300 ms of real time, converted to beats
    /// at the score's original BPM (no tempo scaling — sweepMissed is called
    /// with the same `currentBeat` that `ingest` works in, which is already in
    /// original-tempo beat space).
    ///
    /// - Parameter currentBeat: Current playback position in original-tempo beats.
    /// - Returns: IDs of notes newly marked missed by this sweep.
    public func sweepMissed(currentBeat: Double) -> [UUID] {
        let lateWindowBeats = 0.3 * (score.originalBPM / 60.0)
        let cutoff = currentBeat - lateWindowBeats
        let newlyMissed = score.notes.filter {
            $0.beat < cutoff && !consumed.contains($0.id)
        }
        for note in newlyMissed {
            consumed.insert(note.id)
        }
        return newlyMissed.map(\.id)
    }

    /// Aggregate the verdicts collected so far into a `SessionScoreSummary`.
    ///
    /// `notesCorrect` counts verdicts whose `timing` is not `.miss` (any
    /// matched window). `timingAccuracyPercent` is the mean of timing weights
    /// (perfect=1.0, good=0.7, late/early=0.4, miss=0.0) × 100. `composite`
    /// is the mean of the per-note `NoteScore.accuracy` values.
    ///
    /// - Returns: A snapshot summary suitable for the results overlay.
    public func summary() -> SessionScoreSummary {
        let attempted = verdicts.count + extras
        let correct = verdicts.values.filter { $0.timing != .miss }.count
        let totalExpected = max(1, score.notes.count)
        let missed = max(0, score.notes.count - correct)

        let timingValues = verdicts.values.map { weighting(for: $0.timing) }
        let timingPct = timingValues.isEmpty
            ? 0.0
            : (timingValues.reduce(0.0, +) / Double(timingValues.count)) * 100.0

        let composite = aggregate(verdicts.values.map(\.score))

        return SessionScoreSummary(
            notesAttempted: attempted,
            notesCorrect: correct,
            notesMissed: missed,
            notesExtra: extras,
            timingAccuracyPercent: timingPct,
            notesCorrectPercent: 100.0 * Double(correct) / Double(totalExpected),
            composite: composite
        )
    }

    // MARK: - Private Helpers

    /// Classify a signed real-time delta into a timing window.
    private func classify(secDelta: Double) -> TimingClass {
        let mag = Swift.abs(secDelta)
        switch mag {
        case ..<0.060:
            return .perfect
        case ..<0.150:
            return secDelta < 0 ? .early : .good
        case ..<0.300:
            return secDelta < 0 ? .early : .late
        default:
            return .miss
        }
    }

    /// Weight for `timingAccuracyPercent` aggregation.
    private func weighting(for cls: TimingClass) -> Double {
        switch cls {
        case .perfect: return 1.0
        case .good: return 0.7
        case .late, .early: return 0.4
        case .miss: return 0.0
        }
    }

    /// Pick the unconsumed expected note whose `beat` is closest to `currentBeat`.
    ///
    /// Considers only notes within ±300 ms (the widest scoring window) on
    /// either side of `currentBeat`, so distant future notes don't get matched
    /// by an early extra press.
    private func nearestUnconsumed(toBeat currentBeat: Double) -> ExpectedNote? {
        let windowBeats = 0.3 * (score.originalBPM / 60.0)
        let lo = currentBeat - windowBeats
        let hi = currentBeat + windowBeats
        var best: ExpectedNote?
        var bestDist = Double.infinity
        for note in score.notes where !consumed.contains(note.id) {
            guard note.beat >= lo && note.beat <= hi else { continue }
            let dist = Swift.abs(note.beat - currentBeat)
            if dist < bestDist {
                bestDist = dist
                best = note
            }
        }
        return best
    }

    /// Convert a MIDI note number to a swar string relative to the tonic Sa.
    ///
    /// Uses the canonical 12-tone Hindustani sargam mapping
    /// (Sa, re, Re, ga, Ga, Ma, Ma#, Pa, dha, Dha, ni, Ni). Lower-case denotes
    /// flat (komal) variants. Octave offsets are not annotated — `ScoringAdapter`
    /// only needs a stable label per pitch class for `NoteScoreCalculator`.
    private func swarString(forMIDI midi: UInt8, tonicSa: UInt8) -> String {
        let semitone = ((Int(midi) - Int(tonicSa)) % 12 + 12) % 12
        let table: [String] = [
            "Sa", "re", "Re", "ga", "Ga", "Ma",
            "Ma#", "Pa", "dha", "Dha", "ni", "Ni"
        ]
        return table[semitone]
    }

    /// Aggregate per-note `NoteScore` values into a single composite score.
    ///
    /// Uses the arithmetic mean of `accuracy`, with the most-recent expected/
    /// detected note labels for display. Returns a "missed" sentinel if there
    /// are no scores yet.
    private func aggregate(_ scores: [NoteScore]) -> NoteScore {
        guard !scores.isEmpty else {
            return NoteScoreCalculator.missedNote(expectedNote: "Sa")
        }
        let meanAccuracy = scores.map(\.accuracy).reduce(0.0, +) / Double(scores.count)
        let meanPitchDev = scores.map(\.pitchDeviationCents).reduce(0.0, +) / Double(scores.count)
        let meanTimingDev = scores.map(\.timingDeviationSeconds).reduce(0.0, +) / Double(scores.count)
        let meanDurDev = scores.map(\.durationDeviation).reduce(0.0, +) / Double(scores.count)
        let last = scores[scores.count - 1]
        return NoteScore(
            grade: NoteGrade.from(accuracy: meanAccuracy),
            accuracy: meanAccuracy,
            pitchDeviationCents: meanPitchDev,
            timingDeviationSeconds: meanTimingDev,
            durationDeviation: meanDurDev,
            expectedNote: last.expectedNote,
            detectedNote: last.detectedNote,
            isOutOfRaga: nil
        )
    }
}
