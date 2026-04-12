import Foundation
import SwiftData

/// XP history entry. Append-only (never delete per CloudKit rules).
///
/// Each entry records a single XP award event with its source and timestamp.
/// All fields have explicit defaults for CloudKit compatibility.
///
/// ## CloudKit Compatibility
/// - All fields have explicit default values.
/// - `source` stores `XPSource.rawValue` as a String (enum compatibility).
/// - Append-only: entries are never deleted or modified after creation.
@Model
final class XPEntry {
    /// Unique identifier (auto-generated UUID).
    var id: UUID = UUID()

    /// XP amount awarded in this entry.
    var amount: Int = 0

    /// XP source type stored as `XPSource` rawValue string.
    var source: String = ""

    /// Associated entity ID (lesson ID, song ID, etc.).
    var sourceId: String = ""

    /// Timestamp when the XP was earned.
    var earnedAt: Date = Date()

    /// Creates a new XP history entry.
    ///
    /// - Parameters:
    ///   - amount: XP amount to record. Must be positive for valid awards.
    ///   - source: `XPSource` rawValue identifying what triggered the award.
    ///   - sourceId: ID of the associated lesson, song, or achievement.
    init(amount: Int = 0, source: String = "", sourceId: String = "") {
        self.id = UUID()
        self.amount = amount
        self.source = source
        self.sourceId = sourceId
        self.earnedAt = Date()
    }
}
