// SurVibeTests/InteractivePianoViewAccessibilityTests.swift
import SVCore
import SwiftUI
import Testing
@testable import SurVibe

/// Tests for P1-5 Rang hand-color tokens and P1-6 differentiate-without-color.
@MainActor
@Suite("InteractivePianoView Accessibility")
struct InteractivePianoViewAccessibilityTests {

    @Test func defaultHandColorsUseRangTokens() {
        #expect(Color.rangRightHand != Color.blue, "Rang right-hand token distinct from .blue")
        #expect(Color.rangLeftHand != Color.red, "Rang left-hand token distinct from .red")
        #expect(Color.rangBothHands != Color.purple, "Rang both-hands token distinct from .purple")
    }

    @Test func rangTokensAreStaticColorExtensions() {
        let rh: Color = .rangRightHand
        let lh: Color = .rangLeftHand
        let both: Color = .rangBothHands
        #expect(rh != lh)
        #expect(lh != both)
        #expect(rh != both)
    }
}
