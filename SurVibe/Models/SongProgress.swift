import Foundation
import os
import SVCore
import SwiftData

/// Module-level logger for SongProgress model mutations.
private let songProgressLogger = Logger.survibe(category: "SongProgressModel")

/// Tracks progress on a song. Max-wins merge for bestScore and timesPlayed.
@Model
final class SongProgress {
    var id: UUID = UUID()
    var songId: String = ""
    var songTitle: String = ""
    var bestScore: Double = 0.0
    var timesPlayed: Int = 0
    var lastPlayedAt: Date = Date()
    /// One-way completion flag (false -> true only). Use `markCompleted()` to set.
    private(set) var isCompleted: Bool = false
    /// User-overridden Sa (tonic) frequency in Hz for this song, or nil to use the
    /// song's default derived from `keySignatureRaw`. Persists the *effective* Hz
    /// (grid × cents factor); decomposition happens in `TanpuraController`.
    var preferredSaHz: Double? = nil

    // MARK: - Per-Song Learner Preferences

    /// Which hands the learner practices: "both", "right", or "left".
    var preferredHands: String = "both"

    /// Playback speed as a multiplier of the song's BPM (e.g. 0.75 = 75 %).
    /// Clamping to a valid range is enforced by the ViewModel, not the model.
    var preferredTempoScale: Double = 1.0

    /// Index into the song's learner-track array for the preferred track.
    var preferredLearnerTrackIndex: Int = 0

    /// Whether wait-mode is active: playback pauses until the learner plays
    /// the correct note before advancing.
    var waitModeEnabled: Bool = false

    /// Whether the metronome click track is audible during play-along.
    var clickTrackEnabled: Bool = false

    /// Mix level for the click track: "soft", "normal", or "loud".
    var clickTrackLevel: String = "normal"

    /// Whether the tanpura drone is active during play-along.
    var tanpuraEnabled: Bool = false

    /// Raga name used to configure the tanpura drone; empty string means
    /// the session default is used.
    var tanpuraRaga: String = ""

    /// First beat (0-based) of the loop region, or nil when no loop is set.
    var loopRegionStart: Int?

    /// Last beat (inclusive, 0-based) of the loop region, or nil when no loop
    /// is set. Always >= `loopRegionStart` when both are non-nil.
    var loopRegionEnd: Int?

    init(
        songId: String = "",
        songTitle: String = ""
    ) {
        self.id = UUID()
        self.songId = songId
        self.songTitle = songTitle
        self.bestScore = 0.0
        self.timesPlayed = 0
        self.lastPlayedAt = Date()
        self.isCompleted = false
    }

    /// Record a play session. Uses max-wins for bestScore.
    func recordPlay(score: Double) {
        bestScore = max(bestScore, score)
        timesPlayed += 1
        lastPlayedAt = Date()
        let scoreStr = String(format: "%.1f", score)
        let bestStr = String(format: "%.1f", bestScore)
        let sid = self.songId
        songProgressLogger.debug(
            "Play: \(sid, privacy: .public) score=\(scoreStr, privacy: .public) best=\(bestStr, privacy: .public)"
        )
    }

    /// Mark the song as completed. One-way: once true, cannot revert to false.
    func markCompleted() {
        guard !isCompleted else { return }
        isCompleted = true
    }
}
