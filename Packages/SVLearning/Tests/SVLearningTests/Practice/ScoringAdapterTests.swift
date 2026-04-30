import Foundation
import Testing
@testable import SVLearning
import SVAudio
import SVCore

#if canImport(Darwin)
import Darwin
#endif

// MARK: - Test helpers

/// Convert real-time seconds to mach-absolute-time tick count.
private func secondsToTicks(_ seconds: Double) -> UInt64 {
    #if canImport(Darwin)
    var info = mach_timebase_info_data_t(numer: 0, denom: 0)
    mach_timebase_info(&info)
    let numer = info.numer == 0 ? UInt32(1) : info.numer
    let denom = info.denom == 0 ? UInt32(1) : info.denom
    let nanos = seconds * 1_000_000_000.0
    return UInt64((nanos * Double(denom) / Double(numer)).rounded())
    #else
    return UInt64((seconds * 1_000_000_000.0).rounded())
    #endif
}

/// Build a `LearnerScore` with a single expected note at `beat` with `midiNote`.
private func makeScore(noteAt beat: Double, midiNote: UInt8, bpm: Double = 120.0) -> LearnerScore {
    let note = ExpectedNote(
        beat: beat,
        durationBeats: 1.0,
        midiNote: midiNote,
        measureNumber: 1
    )
    return LearnerScore(notes: [note], originalBPM: bpm, beatsPerMeasure: 4)
}

/// Build a `LearnerScore` with multiple notes.
private func makeScore(notes: [(Double, UInt8)], bpm: Double = 120.0) -> LearnerScore {
    let expected = notes.map { beat, midi in
        ExpectedNote(beat: beat, durationBeats: 1.0, midiNote: midi, measureNumber: 1)
    }
    return LearnerScore(notes: expected, originalBPM: bpm, beatsPerMeasure: 4)
}

// MARK: - Tests

@MainActor
struct ScoringAdapterTests {

    @Test func hostTimeToBeatConversionAtHalfSpeed() {
        // beat 4 at 120 BPM, played at 0.5x → real time = 8 seconds.
        let score = makeScore(noteAt: 4.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score, tonicSaPitch: 60)
        let start = HostTime(rawTicks: 0)
        let now = HostTime(rawTicks: secondsToTicks(8.0))

        let v = adapter.ingest(
            midiNote: 60, velocity: 90,
            hostTime: now, sequencerStartHostTime: start,
            currentTempoScale: 0.5
        )
        #expect(v?.timing == .perfect)
    }

    @Test func wrongPitchMissesAccuracy() {
        // 120 BPM, beat 1 → 0.5 seconds real time. Press 0.5s in but with D instead of C.
        let score = makeScore(noteAt: 1.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)

        let v = adapter.ingest(
            midiNote: 62 /* D */, velocity: 90,
            hostTime: HostTime(rawTicks: secondsToTicks(0.5)),
            sequencerStartHostTime: HostTime(rawTicks: 0),
            currentTempoScale: 1.0
        )
        // Expect a verdict (timing is in window) but composite accuracy is low
        // because pitchDeviationCents = 200 cents -> pitchAccuracy near 0.
        #expect(v != nil)
        #expect((v?.score.accuracy ?? 1.0) < 0.5)
    }

    @Test func sweepMissedMarksUnplayedNotes() {
        let score = makeScore(noteAt: 1.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)
        let missed = adapter.sweepMissed(currentBeat: 5.0)
        #expect(missed.count == 1)
    }

    @Test func nextExpectedReturnsUpcomingNote() {
        let score = makeScore(notes: [(1.0, 60), (2.0, 62), (3.0, 64)])
        let adapter = ScoringAdapter(score: score)
        let next = adapter.nextExpected(afterBeat: 1.5)
        #expect(next?.midiNote == 62)
    }

    @Test func extraNotesIncrementCounter() {
        // Single expected note far in the future (beat 10 = 5s @ 120 BPM, 1x).
        // Press at t=0 → no candidate in window → extras++.
        let score = makeScore(noteAt: 10.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)
        let v = adapter.ingest(
            midiNote: 60, velocity: 90,
            hostTime: HostTime(rawTicks: 0),
            sequencerStartHostTime: HostTime(rawTicks: 0),
            currentTempoScale: 1.0
        )
        #expect(v == nil)
        let summary = adapter.summary()
        #expect(summary.notesExtra == 1)
    }

    @Test func tightWindowPerfect() {
        // Beat 1 at 120 BPM = 0.5s real time. Press at exactly 0.5s → 0 ms delta → perfect.
        let score = makeScore(noteAt: 1.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)
        let v = adapter.ingest(
            midiNote: 60, velocity: 90,
            hostTime: HostTime(rawTicks: secondsToTicks(0.5)),
            sequencerStartHostTime: HostTime(rawTicks: 0),
            currentTempoScale: 1.0
        )
        #expect(v?.timing == .perfect)
    }

    @Test func mediumWindowGood() {
        // Beat 1 = 0.5s; press at 0.6s → +100 ms late → .good.
        let score = makeScore(noteAt: 1.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)
        let v = adapter.ingest(
            midiNote: 60, velocity: 90,
            hostTime: HostTime(rawTicks: secondsToTicks(0.6)),
            sequencerStartHostTime: HostTime(rawTicks: 0),
            currentTempoScale: 1.0
        )
        #expect(v?.timing == .good)
    }

    @Test func mediumWindowEarly() {
        // Beat 1 = 0.5s; press at 0.4s → -100 ms early → .early.
        let score = makeScore(noteAt: 1.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)
        let v = adapter.ingest(
            midiNote: 60, velocity: 90,
            hostTime: HostTime(rawTicks: secondsToTicks(0.4)),
            sequencerStartHostTime: HostTime(rawTicks: 0),
            currentTempoScale: 1.0
        )
        #expect(v?.timing == .early)
    }

    @Test func lateButNotMissed() {
        // Beat 1 = 0.5s; press at 0.7s → +200 ms late → .late.
        let score = makeScore(noteAt: 1.0, midiNote: 60)
        let adapter = ScoringAdapter(score: score)
        let v = adapter.ingest(
            midiNote: 60, velocity: 90,
            hostTime: HostTime(rawTicks: secondsToTicks(0.7)),
            sequencerStartHostTime: HostTime(rawTicks: 0),
            currentTempoScale: 1.0
        )
        #expect(v?.timing == .late)
    }
}
