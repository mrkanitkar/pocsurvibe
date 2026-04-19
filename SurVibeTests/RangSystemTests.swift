import Foundation
import SVCore
import SwiftData
import Testing

@testable import SurVibe

/// Tests for `RangSystem` level progression and XP-to-rang calculations.
///
/// Uses in-memory `ModelContainer` with a pre-created `UserProfile`.
/// Verifies that rang recalculation correctly detects level-ups,
/// returns nil when no change, and reports accurate progress fractions.
/// Serialized + shared container — see `SwiftDataTestContainer.swift`
/// for why per-test `isStoredInMemoryOnly` containers crash the host.
@Suite("RangSystem Tests", .serialized)
@MainActor
struct RangSystemTests {

    // MARK: - Helpers

    /// Creates a RangSystem with a UserProfile at the given XP/rang.
    private func makeSystem(xp: Int, rang: Int = 1) throws -> (RangSystem, ModelContext) {
        let context = try SwiftDataTestContainer.freshContext()
        let profile = UserProfile()
        profile.totalXP = xp
        profile.currentRang = rang
        context.insert(profile)
        try context.save()
        return (RangSystem(modelContext: context), context)
    }

    // MARK: - Current Rang

    @Test("currentRang returns Neel at 0 XP")
    func currentRangAtZero() throws {
        let (system, _) = try makeSystem(xp: 0)
        #expect(system.currentRang == .neel)
    }

    @Test("currentRang returns Hara at 500 XP")
    func currentRangAtHara() throws {
        let (system, _) = try makeSystem(xp: 500)
        #expect(system.currentRang == .hara)
    }

    @Test("currentRang returns Sona at 10000 XP")
    func currentRangAtMax() throws {
        let (system, _) = try makeSystem(xp: 10000)
        #expect(system.currentRang == .sona)
    }

    // MARK: - XP To Next Rang

    @Test("xpToNextRang correct at Neel level")
    func xpToNextRangNeel() throws {
        let (system, _) = try makeSystem(xp: 200)
        #expect(system.xpToNextRang == 300)  // 500 - 200
    }

    @Test("xpToNextRang is 0 at Sona (max level)")
    func xpToNextRangMax() throws {
        let (system, _) = try makeSystem(xp: 15000)
        #expect(system.xpToNextRang == 0)
    }

    // MARK: - Progress To Next Rang

    @Test("progressToNextRang at midpoint")
    func progressMidpoint() throws {
        let (system, _) = try makeSystem(xp: 250)
        // Neel range: 0-500, at 250 = 50%
        let progress = system.progressToNextRang
        #expect(progress > 0.49)
        #expect(progress < 0.51)
    }

    @Test("progressToNextRang is 1.0 at Sona")
    func progressAtMax() throws {
        let (system, _) = try makeSystem(xp: 12000)
        #expect(system.progressToNextRang == 1.0)
    }

    // MARK: - Recalculate

    @Test("recalculate returns new level on threshold cross")
    func recalculateReturnsLevelUp() throws {
        let (system, _) = try makeSystem(xp: 500, rang: 1)
        let result = system.recalculate()
        #expect(result == .hara)
    }

    @Test("recalculate returns nil when no change")
    func recalculateReturnsNilNoChange() throws {
        let (system, _) = try makeSystem(xp: 300, rang: 1)
        let result = system.recalculate()
        #expect(result == nil)
    }

    @Test("recalculate updates stored rang on profile")
    func recalculateUpdatesProfile() throws {
        let (system, context) = try makeSystem(xp: 2000, rang: 1)
        system.recalculate()

        let descriptor = FetchDescriptor<UserProfile>()
        let profile = try context.fetch(descriptor).first
        #expect(profile?.currentRang == 3)  // Peela
    }

    @Test("recalculate applies max-wins (rang never decreases)")
    func recalculateMaxWins() throws {
        // Profile has rang 4 (Lal) but XP only qualifies for rang 2 (Hara)
        let (system, context) = try makeSystem(xp: 600, rang: 4)
        let result = system.recalculate()
        #expect(result == nil)  // No level-up since stored > computed

        let descriptor = FetchDescriptor<UserProfile>()
        let profile = try context.fetch(descriptor).first
        #expect(profile?.currentRang == 4)  // Still Lal, not downgraded
    }
}
