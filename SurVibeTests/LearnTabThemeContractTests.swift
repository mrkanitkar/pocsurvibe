import Foundation
import Testing

/// Static-source Learn-tab theme-contract guard.
///
/// Asserts post-Phase-3 Learn-tab views contain no disallowed hardcoded
/// color patterns. Mirrors the LatencyContractTests pattern: fast,
/// deterministic, no UI.
///
/// Comment-only lines (starting with `//`) are stripped before searching so
/// /// doc comments mentioning banned patterns don't trigger false positives.
struct LearnTabThemeContractTests {

    // MARK: - File lists

    private static let learnTabFiles: [String] = [
        "SurVibe/Learn/LessonCardView.swift",
        "SurVibe/Learn/LessonLibraryView.swift",
        "SurVibe/Learn/Curriculum/LessonRowView.swift",
        "SurVibe/Learn/Curriculum/CurriculumCardView.swift",
        "SurVibe/Learn/LessonDetailView.swift",
        "SurVibe/Learn/Curriculum/CurriculumDetailView.swift",
        "SurVibe/Learn/LessonStepView.swift",
        "SurVibe/Learn/LessonStepView+StepContent.swift",
        "SurVibe/Learn/LessonCompletionView.swift",
        "SurVibe/Learn/Steps/IntroStepView.swift",
        "SurVibe/Learn/Steps/ListenStepView.swift",
        "SurVibe/Learn/Steps/QuizStepView.swift",
        "SurVibe/Learn/Steps/ExerciseStepView.swift",
        "SurVibe/Learn/Steps/ExerciseStepView+Subviews.swift",
        "SurVibe/Learn/Steps/SingStepView.swift",
        "SurVibe/Learn/ConfettiView.swift"
    ]

    private static let latencyConservativeFiles: [String] = [
        "SurVibe/Learn/Steps/SingStepView.swift",
        "SurVibe/Learn/Steps/ExerciseStepView.swift",
        "SurVibe/Learn/Steps/ExerciseStepView+Subviews.swift"
    ]

    // MARK: - Banned patterns

    private static let bannedPatterns: [String] = [
        #"Color\(\.secondarySystemBackground\)"#,
        #"Color\(\.tertiarySystemBackground\)"#,
        #"Color\(\.systemGray[0-9]?\)"#,
        #"\.foregroundStyle\(\.green\)"#,
        #"\.foregroundStyle\(\.red\)"#,
        #"\.foregroundStyle\(\.blue\)"#,
        #"\.foregroundStyle\(\.pink\)"#,
        #"\.foregroundStyle\(\.purple\)"#,
        #"\.foregroundStyle\(\.orange\)"#,
        #"\.tint\(\.green\)"#,
        #"\.tint\(\.pink\)"#,
        #"\.tint\(\.purple\)"#,
        #"\.tint\(\.orange\)"#,
        #"Color\(red: *0\."#
    ]

    // MARK: - Helpers

    /// Project root derived from this file's path so the test works from any
    /// worktree (`#filePath` resolves to the actual on-disk location of the
    /// test source file at compile time).
    private static let projectRoot: String = {
        let testFile = URL(fileURLWithPath: #filePath)
        // SurVibeTests/LearnTabThemeContractTests.swift → up 2 levels = project root
        return testFile.deletingLastPathComponent().deletingLastPathComponent().path
    }()

    /// Load a file and strip comment-only lines so /// doc comments mentioning
    /// a banned pattern don't false-positive.
    private static func codeOnly(for path: String) -> String? {
        let full = "\(projectRoot)/\(path)"
        guard let content = try? String(contentsOfFile: full, encoding: .utf8) else {
            return nil
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                return !trimmed.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    // MARK: - Tests

    /// Contract: No Learn-tab file contains banned color hardcodes.
    @Test func noLearnTabFileContainsBannedColorHardcodes() throws {
        for path in Self.learnTabFiles {
            guard let code = Self.codeOnly(for: path) else { continue }
            for pattern in Self.bannedPatterns {
                let regex = try Regex(pattern)
                #expect(
                    code.firstMatch(of: regex) == nil,
                    "\(path) contains banned pattern: \(pattern)"
                )
            }
        }
    }

    /// Contract: The 3 latency-conservative files must NOT read
    /// `@Environment(AppThemeManager.self)`. They receive theme colors as
    /// `let` params from the parent (spec §5.5, §7).
    @Test func latencyConservativeViewsDoNotReadThemeEnvironment() throws {
        let forbidden = "@Environment(AppThemeManager.self)"
        for path in Self.latencyConservativeFiles {
            guard let code = Self.codeOnly(for: path) else { continue }
            #expect(
                !code.contains(forbidden),
                "\(path) must receive theme colors as let params (latency-conservative)"
            )
        }
    }
}
