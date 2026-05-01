import Foundation
import os
import SVCore
import SwiftData

/// Module-level logger for SongProgress model mutations.
private let songProgressLogger = Logger.survibe(category: "SongProgressModel")

// MARK: - Conflict Resolution
//
// SongProgress uses CloudKit's default whole-record last-write-wins.
// Per-field merge is NOT possible — the entire record is one CKRecord.
//
// Additive fields (`bestScore`, `timesPlayed`, `xpEarnedTotal`) are
// merged at the application level inside `recordPlay(...)` via max()
// and additive increments. Pref fields (preferredTempoScale, etc.)
// use last-write-wins as the desired UX.
//
// DO NOT introduce per-field merge expectations — they cannot be
// honored at the persistence layer.

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

    /// Preferred hand isolation mode: "both", "rh", or "lh".
    var preferredHands: String = "both"
    /// Preferred tempo scaling factor, clamped to [0.5, 1.5].
    var preferredTempoScale: Double = 1.0
    /// Index of the preferred learner track in a multi-track arrangement.
    var preferredLearnerTrackIndex: Int = 0
    /// Whether wait mode is enabled for this song.
    var waitModeEnabled: Bool = false
    /// Whether the click track is enabled for this song.
    var clickTrackEnabled: Bool = false
    /// Click track loudness preset: "soft", "normal", or "loud".
    var clickTrackLevel: String = "normal"
    /// Whether the tanpura drone is enabled for this song.
    var tanpuraEnabled: Bool = false
    /// Raga override for the tanpura drone. Empty string uses song default.
    var tanpuraRaga: String = ""
    /// Start bar index of the loop region, or nil for no loop.
    var loopRegionStart: Int? = nil
    /// End bar index of the loop region, or nil for no loop.
    var loopRegionEnd: Int? = nil

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
