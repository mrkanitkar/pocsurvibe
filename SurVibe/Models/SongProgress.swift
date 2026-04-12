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
