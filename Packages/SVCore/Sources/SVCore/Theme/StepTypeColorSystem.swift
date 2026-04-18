import SwiftUI

/// Lesson step kind — matches the `stepType` string persisted on `LessonStep`.
///
/// Raw values are lowercase and must stay stable; persisted content relies on them.
/// All 7 cases appear in production content (`seed-lessons.json`).
public enum LessonStepKind: String, Sendable, CaseIterable {
    case intro
    case read
    case listen
    case exercise
    case practice
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
/// learning signal and must remain stable across all app themes. Themes
/// never override these.
///
/// **7 kinds → 5 colors, grouped by pedagogical phase.** Icons in the
/// view differentiate kinds within a color group. The grouping mirrors
/// the existing view-level architecture (`introReadContent` already
/// renders both `intro` and `read`; `ExerciseStepView` already handles
/// both `exercise` and `practice`).
///
/// | Phase | Kinds | Color |
/// |---|---|---|
/// | Receptive / informational (text) | intro, read | `.blue` |
/// | Receptive / informational (audio) | listen | `.purple` |
/// | Active / kinesthetic | exercise, practice | `.green` |
/// | Vocal | sing | `.pink` |
/// | Evaluation | quiz | `.yellow` |
///
/// ## Usage
/// ```swift
/// let color = StepTypeColorSystem.color(for: .exercise)  // .green
/// let fallback = StepTypeColorSystem.color(forStepType: "unknown", fallback: .gray)
/// ```
public enum StepTypeColorSystem {

    /// Canonical color for a given step kind.
    ///
    /// - Parameter kind: The pedagogical step kind whose canonical color to retrieve.
    /// - Returns: The pedagogical color associated with that kind.
    public static func color(for kind: LessonStepKind) -> Color {
        switch kind {
        // Receptive / informational (text) — blue
        case .intro:    return .blue
        case .read:     return .blue       // same bucket as intro

        // Receptive / informational (audio) — purple
        case .listen:   return .purple

        // Active / kinesthetic — green
        case .exercise: return .green
        case .practice: return .green      // same bucket as exercise

        // Vocal — pink
        case .sing:     return .pink

        // Evaluation — yellow (matches existing helper convention)
        case .quiz:     return .yellow
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
