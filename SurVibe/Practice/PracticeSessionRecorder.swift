import Foundation
import SwiftData
import SVLearning
import os.log

/// Records practice session results to SwiftData models.
///
/// After a practice session completes, this recorder persists the results
/// to three models: `RiyazEntry` (daily practice log), `SongProgress`
/// (per-song high scores), and `UserProfile` (XP accumulation).
///
/// Lives in the main app target because it requires `ModelContext` access
/// for SwiftData persistence. Pure scoring computation is in `SVLearning`.
/// Bundles song metadata for a practice session recording.
///
/// Groups the four song-related parameters into a single value type,
/// keeping `PracticeSessionRecorder.recordSession` under the 5-parameter limit.
struct SessionSongInfo: Sendable {
    /// Unique identifier of the practiced song.
    let songId: String

    /// Display title of the practiced song.
    let songTitle: String

    /// Raga name of the song (for the practice log).
    let ragaName: String

    /// Song difficulty level (1-5).
    let difficulty: Int
}

@MainActor
final class PracticeSessionRecorder {
    // MARK: - Properties

    private let modelContext: ModelContext

    private static let logger = Logger(
        subsystem: "com.survibe",
        category: "PracticeSessionRecorder"
    )

    // MARK: - Initialization

    /// Create a recorder with the given SwiftData model context.
    ///
    /// - Parameter modelContext: The model context for persisting practice data.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// Record a completed practice session.
    ///
    /// Persists three records:
    /// 1. **RiyazEntry** — daily practice log (additive-only)
    /// 2. **SongProgress** — per-song best score (max-wins)
    /// 3. **UserProfile** — XP accumulation
    ///
    /// - Parameters:
    ///   - songInfo: Bundled song metadata (id, title, raga, difficulty).
    ///   - durationMinutes: Length of the practice session in minutes.
    ///   - noteScores: Array of individual note scores from the session.
    func recordSession(
        songInfo: SessionSongInfo,
        durationMinutes: Int,
        noteScores: [NoteScore]
    ) {
        let accuracy = PracticeScoring.averageAccuracy(scores: noteScores)
        let xp = PracticeScoring.xpEarned(
            accuracy: accuracy,
            difficulty: songInfo.difficulty
        )

        // 1. Create RiyazEntry (additive-only daily log)
        let entry = RiyazEntry(
            date: Date(),
            durationMinutes: durationMinutes,
            notesPlayed: noteScores.count,
            accuracyPercent: accuracy * 100.0,
            xpEarned: xp,
            raagPracticed: songInfo.ragaName
        )
        modelContext.insert(entry)

        // 2. Update SongProgress (max-wins for bestScore)
        let songProgress = fetchOrCreateSongProgress(
            songId: songInfo.songId,
            songTitle: songInfo.songTitle
        )
        songProgress.recordPlay(score: accuracy * 100.0)

        // Mark completed if achieved 3+ stars (>= 60% accuracy)
        let stars = PracticeScoring.starRating(accuracy: accuracy)
        if stars >= 3 {
            songProgress.markCompleted()
        }

        // Note: XP is now awarded by GamificationService in PracticeSessionViewModel.completePractice().
        // PracticeSessionRecorder only handles RiyazEntry + SongProgress persistence.

        Self.logger.info(
            "Session recorded: song=\(songInfo.songId) accuracy=\(accuracy) xp=\(xp) notes=\(noteScores.count)"
        )
    }

    // MARK: - Private Methods

    /// Fetch existing SongProgress or create a new one.
    ///
    /// Queries by `songId` and returns the first match, or creates a new
    /// `SongProgress` entry if none exists.
    ///
    /// - Parameters:
    ///   - songId: Unique identifier of the song.
    ///   - songTitle: Display title for the new progress record.
    /// - Returns: The existing or newly created `SongProgress`.
    private func fetchOrCreateSongProgress(songId: String, songTitle: String) -> SongProgress {
        let descriptor = FetchDescriptor<SongProgress>(
            predicate: #Predicate { $0.songId == songId }
        )

        do {
            if let existing = try modelContext.fetch(descriptor).first {
                return existing
            }
        } catch {
            Self.logger.error("Failed to fetch SongProgress for \(songId): \(error.localizedDescription)")
        }

        let progress = SongProgress(songId: songId, songTitle: songTitle)
        modelContext.insert(progress)
        return progress
    }

    /// Add XP to the current user profile.
    ///
    /// Fetches the first `UserProfile` from the store and adds XP.
    /// If no profile exists (edge case), logs a warning and skips.
    ///
    /// - Parameter xp: XP amount to add (must be positive).
    private func updateUserXP(_ xp: Int) {
        let descriptor = FetchDescriptor<UserProfile>(
            sortBy: [SortDescriptor(\UserProfile.createdAt)]
        )

        guard let profile = try? modelContext.fetch(descriptor).first else {
            Self.logger.warning("No UserProfile found — cannot add XP")
            return
        }

        profile.addXP(xp)
    }
}
