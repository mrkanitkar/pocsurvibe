import SwiftUI

/// Lesson step kind — matches the `stepType` string persisted on `LessonStep`.
///
/// Raw values are lowercase and must stay stable; persisted content relies on them.
public enum LessonStepKind: String, Sendable, CaseIterable {
    case intro
    case exercise
    case listen
    case sing
    case quiz

    /// Parse the `String` raw value stored on `LessonStep.stepType`.
    ///
    /// Accepts case-insensitive input (e.g., `"Intro"`, `"INTRO"`, `"intro"`
    /// all map to `.intro`). Returns `nil` for unknown types — callers fall
    /// back to a neutral color.
    public init?(stepType: String) {
        self.init(rawValue: stepType.lowercased())
    }
}

/// Pedagogical colors for lesson step types — theme-independent.
///
/// Parallels `RangColorSystem` and `SargamColorMap`: the colors convey a
/// learning signal (intro = informational, exercise = active, listen =
/// receptive, sing = expressive, quiz = attention) and must remain stable
/// across all app themes. Themes never override these.
///
/// ## Usage
/// ```swift
/// let color = StepTypeColorSystem.color(for: .exercise)  // .green
/// let fallback = StepTypeColorSystem.color(forStepType: "unknown", fallback: .gray)
/// ```
public enum StepTypeColorSystem {

    /// Canonical color for a given step kind.
    ///
    /// - Parameter kind: The step kind.
    /// - Returns: The pedagogical color associated with that kind.
    public static func color(for kind: LessonStepKind) -> Color {
        switch kind {
        case .intro:    return .blue    // informational
        case .exercise: return .green   // active / kinesthetic
        case .listen:   return .purple  // receptive / contemplative
        case .sing:     return .pink    // vocal / expressive
        case .quiz:     return .orange  // attention / evaluation
        }
    }

    /// Convenience for call sites that hold the raw `stepType` string from `LessonStep`.
    ///
    /// - Parameters:
    ///   - stepType: The raw step-type string (case-insensitive).
    ///   - fallback: The color returned for unknown step types. Defaults to `.gray`.
    /// - Returns: The pedagogical color for the kind, or `fallback` if unrecognized.
    public static func color(forStepType stepType: String, fallback: Color = .gray) -> Color {
        guard let kind = LessonStepKind(stepType: stepType) else { return fallback }
        return color(for: kind)
    }
}
