import Foundation

/// Errors emitted by `Quantizer.quantize`.
public enum QuantizeError: Error, Sendable, Equatable {
    /// Tempo was zero or negative.
    case invalidBPM
    /// Reserved for future use; the quantizer currently returns an empty
    /// `QuantizedScore` rather than failing on empty input.
    case noNotes
}

/// Pure-Swift quantizer: maps wall-clock-timed `RecordedNote`s onto a beat
/// grid and groups them into measures.
///
/// Input is a flat array of `RecordedNote`s with real timestamps plus a
/// user-chosen `bpm`, `timeSignature`, and `grid` resolution. Output is a
/// `QuantizedScore` whose notes have been snapped to the grid, assigned a
/// discrete `MusicalDuration`, split between treble (MIDI ≥60) and bass
/// (MIDI <60) staves, and bucketed into measures with `startBeat` rebased
/// to the start of each measure.
///
/// This is a stateless, `MainActor`-free namespace — every method is `static`
/// and free of side effects so it can be called from any isolation domain.
public enum Quantizer {

    /// Quantizes a flat array of recorded notes into a `QuantizedScore`.
    ///
    /// Each note's `onTimeSec` is converted to beats, snapped to `grid`, and
    /// assigned the closest `MusicalDuration` to its measured length. Notes
    /// with MIDI ≥60 land on the treble staff (voice 1); notes <60 land on
    /// the bass staff (voice 2), matching the v1 PlayAlong split.
    ///
    /// - Parameters:
    ///   - notes: Recorded notes with wall-clock timestamps relative to the
    ///     take start.
    ///   - sustain: CC64 events captured alongside the notes. Currently
    ///     accepted but not yet woven into the output (reserved for a future
    ///     pass that emits MusicXML pedal marks).
    ///   - bpm: Tempo in beats per minute. Must be > 0.
    ///   - timeSignature: Time signature applied to every measure of the score.
    ///   - grid: Quantization grid resolution (1/8 or 1/16).
    /// - Returns: `.success(QuantizedScore)` on valid input; `.failure` if
    ///   `bpm` is non-positive.
    public static func quantize(
        notes: [RecordedNote],
        sustain: [RecordedSustainEvent],
        bpm: Int,
        timeSignature: TimeSignature,
        grid: QuantizeGrid
    ) -> Result<QuantizedScore, QuantizeError> {
        _ = sustain  // reserved for a future MusicXML pedal-mark pass
        guard bpm > 0 else { return .failure(.invalidBPM) }

        let beatLengthSec = 60.0 / Double(bpm)
        let gridBeats = grid.beats

        var quantized: [QuantizedNote] = []
        quantized.reserveCapacity(notes.count)
        for note in notes {
            let startBeat = snap(note.onTimeSec / beatLengthSec, to: gridBeats)
            let rawLengthBeats = (note.offTimeSec - note.onTimeSec) / beatLengthSec
            let snappedLength = snap(rawLengthBeats, to: gridBeats)
            let lengthBeats = max(gridBeats, snappedLength)
            let dur = closestDuration(forBeats: lengthBeats)
            let staff: Staff = note.midi >= 60 ? .treble : .bass
            let voice = staff == .treble ? 1 : 2
            quantized.append(QuantizedNote(
                midi: note.midi,
                startBeat: startBeat,
                duration: dur,
                velocity: note.velocity,
                staff: staff,
                voice: voice
            ))
        }

        let beatsPerMeasure = Double(timeSignature.beatsPerMeasure)
        var measures: [QuantizedMeasure] = []
        if !quantized.isEmpty {
            let maxBeat = quantized.map { $0.startBeat + $0.duration.beats }.max() ?? 0
            let measureCount = max(1, Int((maxBeat / beatsPerMeasure).rounded(.up)))
            measures.reserveCapacity(measureCount)
            for measureIndex in 0..<measureCount {
                let lo = Double(measureIndex) * beatsPerMeasure
                let hi = lo + beatsPerMeasure
                let bucket = quantized
                    .filter { $0.startBeat >= lo && $0.startBeat < hi }
                    .map {
                        QuantizedNote(
                            midi: $0.midi,
                            startBeat: $0.startBeat - lo,
                            duration: $0.duration,
                            velocity: $0.velocity,
                            staff: $0.staff,
                            voice: $0.voice
                        )
                    }
                measures.append(QuantizedMeasure(number: measureIndex + 1, notes: bucket))
            }
        }

        return .success(QuantizedScore(bpm: bpm, timeSignature: timeSignature, measures: measures))
    }

    /// Snaps `value` to the nearest multiple of `grid` (rounded-half-to-even
    /// via `Double.rounded()`).
    private static func snap(_ value: Double, to grid: Double) -> Double {
        (value / grid).rounded() * grid
    }

    /// Picks the `MusicalDuration` whose `beats` is closest to `beats`.
    ///
    /// Ties are broken by the order of the candidate list (shortest first).
    private static func closestDuration(forBeats beats: Double) -> MusicalDuration {
        let candidates: [MusicalDuration] = [
            .thirtySecond, .sixteenth, .dottedSixteenth, .eighth, .dottedEighth,
            .tripletEighth, .quarter, .dottedQuarter, .tripletQuarter,
            .half, .dottedHalf, .whole,
        ]
        return candidates.min(by: { abs($0.beats - beats) < abs($1.beats - beats) }) ?? .quarter
    }
}
