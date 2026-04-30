// SurVibe/PlayAlong/Coordinators/SectionLoopController.swift
import Foundation

// MARK: - LoopRegion

/// A 1-indexed, inclusive measure range used by `ArrangementPlayer` to
/// punch-in / punch-out loop a portion of the song during practice.
///
/// Per spec §5.1, both `startMeasure` and `endMeasure` are 1-indexed and
/// inclusive — a `LoopRegion(startMeasure: 5, endMeasure: 8)` loops
/// measures 5, 6, 7, and 8 (in 4/4, that is beats 16..<32 in song time).
public struct LoopRegion: Sendable, Equatable {

    /// First measure of the loop region (1-indexed, inclusive).
    public let startMeasure: Int

    /// Last measure of the loop region (1-indexed, inclusive).
    public let endMeasure: Int

    /// Create a loop region.
    ///
    /// - Parameters:
    ///   - startMeasure: First measure (1-indexed, inclusive).
    ///   - endMeasure: Last measure (1-indexed, inclusive).
    public init(startMeasure: Int, endMeasure: Int) {
        self.startMeasure = startMeasure
        self.endMeasure = endMeasure
    }
}

// MARK: - SectionLoopController

/// Pure value-type calculator that translates a `LoopRegion` (measure
/// units) into beat-space boundaries and decides when playback should
/// wrap back to the loop start.
///
/// Used by `ArrangementPlayer` (Wave 3 Task C3) to implement section
/// looping. Kept as a `Sendable` struct so it can be inspected from any
/// isolation domain — the controller itself owns no mutable state.
struct SectionLoopController: Sendable, Equatable {

    /// The 1-indexed inclusive measure range to loop.
    let region: LoopRegion

    /// Beats per measure for the current song (from `LearnerScore`).
    let beatsPerMeasure: Int

    /// First beat of the loop region (inclusive).
    ///
    /// Measures are 1-indexed, so measure 5 in 4/4 starts at beat 16.
    var startBeat: Double {
        Double((region.startMeasure - 1) * beatsPerMeasure)
    }

    /// One past the last beat of the loop region.
    ///
    /// `endMeasure` is inclusive, so the loop covers
    /// `[startBeat, endBeat)`. For measures 5..8 in 4/4 this is 32.
    var endBeat: Double {
        Double(region.endMeasure * beatsPerMeasure)
    }

    /// Whether playback at `currentBeat` has reached or passed the end of
    /// the loop region and should wrap back to `startBeat`.
    ///
    /// - Parameter currentBeat: The player's current song-time beat.
    /// - Returns: `true` if the player should seek back to `startBeat`.
    func shouldWrap(currentBeat: Double) -> Bool {
        currentBeat >= endBeat
    }
}
