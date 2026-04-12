import Foundation
import os
import SVCore
import SwiftData

/// Module-level logger for UserProfile model mutations.
private let profileLogger = Logger.survibe(category: "UserProfileModel")

/// User profile model for CloudKit sync.
/// All fields have defaults or are optional per CloudKit requirements.
/// Additive-only: XP and rang only increase (max-wins).
@Model
final class UserProfile {
    var id: UUID = UUID()
    var displayName: String = ""
    var currentRang: Int = 1
    var totalXP: Int = 0
    var preferredLanguage: String = "en"
    var createdAt: Date = Date()
    var lastActiveAt: Date = Date()

    /// Whether this user has not yet signed in with Apple.
    var isAnonymous: Bool = true

    /// The Apple ID user identifier from Sign in with Apple.
    /// Empty string when anonymous (CloudKit requires non-optional).
    var appleUserIdentifier: String = ""

    /// Profile image data (stored as Transformable blob in CloudKit).
    @Attribute(.externalStorage) var profileImageData: Data?

    init(
        displayName: String = "",
        preferredLanguage: String = "en"
    ) {
        self.id = UUID()
        self.displayName = displayName
        self.currentRang = 1
        self.totalXP = 0
        self.preferredLanguage = preferredLanguage
        self.createdAt = Date()
        self.lastActiveAt = Date()
    }

    /// Add XP (accumulative, guards against negative amounts).
    /// CloudKit conflict resolution uses max-wins at the sync layer.
    func addXP(_ amount: Int) {
        guard amount > 0 else { return }
        totalXP += amount
        lastActiveAt = Date()
        profileLogger.debug("XP added: \(amount, privacy: .public), total: \(self.totalXP, privacy: .public)")
    }
}
