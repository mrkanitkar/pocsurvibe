import Foundation
import SwiftUI

/// Rang (color) system mapping musical achievement levels to colors.
/// Each level represents a stage of musical proficiency in Indian classical music.
///
/// Usage rules:
/// - Neel, Hara, Lal: Safe for any text size, backgrounds, and icons
/// - Peela, Sona: Use only for backgrounds, large text (18pt+), and icons
///   For body text with Peela/Sona, use the dark variants (peelaDark/sonaDark)
///   which meet WCAG AA contrast requirements
public enum RangLevel: Int, CaseIterable, Sendable {
    case neel = 1    // Beginner — Indigo Blue (#3F51B5)
    case hara = 2    // Developing — Forest Green (#388E3C)
    case peela = 3   // Intermediate — Marigold (#F9A825)
    case lal = 4     // Advanced — Vermillion (#D32F2F)
    case sona = 5    // Master — Gold (#FFB300)

    /// Display name for this rang level.
    public var displayName: String {
        switch self {
        case .neel: "Neel"
        case .hara: "Hara"
        case .peela: "Peela"
        case .lal: "Lal"
        case .sona: "Sona"
        }
    }

    /// Localized description of the proficiency level.
    public var proficiencyLabel: String {
        switch self {
        case .neel: String(localized: "Beginner", bundle: .module)
        case .hara: String(localized: "Developing", bundle: .module)
        case .peela: String(localized: "Intermediate", bundle: .module)
        case .lal: String(localized: "Advanced", bundle: .module)
        case .sona: String(localized: "Master", bundle: .module)
        }
    }

    /// Primary color for this rang level.
    public var color: Color {
        switch self {
        case .neel: .rangNeel
        case .hara: .rangHara
        case .peela: .rangPeela
        case .lal: .rangLal
        case .sona: .rangSona
        }
    }

    /// Safe color for body text — uses dark variants for Peela and Sona
    /// to meet WCAG AA contrast requirements on white backgrounds.
    public var bodyTextColor: Color {
        switch self {
        case .neel: .rangNeel
        case .hara: .rangHara
        case .peela: .rangPeelaDark
        case .lal: .rangLal
        case .sona: .rangSonaDark
        }
    }

    /// Minimum XP threshold to reach this rang level.
    public var xpThreshold: Int {
        switch self {
        case .neel: 0
        case .hara: 500
        case .peela: 2000
        case .lal: 5000
        case .sona: 10000
        }
    }

    /// Determine the rang level for a given XP value.
    public static func level(for xp: Int) -> RangLevel {
        for level in allCases.reversed() where xp >= level.xpThreshold {
            return level
        }
        return .neel
    }
}

// MARK: - Hand-Color Semantic Tokens (P1-5)

/// Semantic color tokens for piano hand-role highlights.
///
/// These tokens replace the legacy `.blue` / `.red` / `.purple` defaults on
/// `InteractivePianoView` with colorblind-aware, WCAG AA compliant hues.
/// They are hue-differentiated (green / orange / purple) so protanopia and
/// deuteranopia users can still distinguish right-hand from left-hand.
/// When `accessibilityDifferentiateWithoutColor` is true, the R / L letter
/// overlay (P1-6) is paired with these tokens.
extension Color {
    /// Right-hand accent token for piano key highlights (P1-5).
    /// WCAG AA ≥ 4.5:1 on white piano keys; hue-differentiated from `rangLeftHand`
    /// for colorblind users. Paired with R/L letter overlay (P1-6) when
    /// `accessibilityDifferentiateWithoutColor` is true.
    public static let rangRightHand = Color(red: 0.20, green: 0.55, blue: 0.25)

    /// Left-hand accent token for piano key highlights (P1-5).
    public static let rangLeftHand = Color(red: 0.75, green: 0.35, blue: 0.10)

    /// Chord / both-hands accent token for simultaneous note highlights (P1-5).
    public static let rangBothHands = Color(red: 0.40, green: 0.20, blue: 0.55)
}
