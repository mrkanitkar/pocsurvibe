import Foundation
import Testing

@testable import SurVibe

/// Tests for the `Hand` enum and `NoteEvent.hand` default field.
///
/// Phase 2 of the PlayAlong redesign separates right-hand (treble/melody)
/// from left-hand (bass/drone) notes. Existing single-hand melody songs
/// should continue to render as right-hand by default.
struct NoteEventHandTests {

    /// Verify both `Hand` enum cases exist and are distinct.
    @Test func handEnumCasesExist() {
        let right = Hand.right
        let left = Hand.left
        #expect(right != left)
        #expect(Hand.allCases.count == 2)
    }

    /// Verify that a `NoteEvent` constructed without a `hand` argument
    /// defaults to `.right` — the safe default for pre-v2 single-hand content.
    @Test func noteEventDefaultsToRightHand() {
        let event = NoteEvent(
            id: UUID(),
            midiNote: 60,
            swarName: "Sa",
            westernName: "C4",
            octave: 4,
            timestamp: 0.0,
            duration: 0.5,
            velocity: 100
        )
        #expect(event.hand == .right)
    }

    /// Verify that an explicit `hand: .left` argument overrides the default.
    @Test func noteEventAcceptsExplicitLeftHand() {
        let event = NoteEvent(
            id: UUID(),
            midiNote: 48,
            swarName: "Sa",
            westernName: "C3",
            octave: 3,
            timestamp: 0.0,
            duration: 0.5,
            velocity: 100,
            hand: .left
        )
        #expect(event.hand == .left)
    }
}
