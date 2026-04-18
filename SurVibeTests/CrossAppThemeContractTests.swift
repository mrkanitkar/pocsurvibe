import Foundation
import Testing

/// Static-source cross-app theme-contract guard.
///
/// Phase 3.5 (Songs + Onboarding + PlayAlong Results + Practice + Components):
/// asserts the refactored views contain no disallowed hardcoded color
/// patterns. Mirrors `LearnTabThemeContractTests` and `LatencyContractTests`
/// patterns: fast, deterministic, no UI.
///
/// Comment-only lines (starting with `//`) are stripped before searching so
/// `///` doc comments mentioning banned patterns don't trigger false positives.
struct CrossAppThemeContractTests {

    // MARK: - File lists

    private static let crossAppFiles: [String] = [
        // Songs (10)
        "SurVibe/Songs/SongCardView.swift",
        "SurVibe/Songs/SongListRow.swift",
        "SurVibe/Songs/DifficultyBadge.swift",
        "SurVibe/Songs/MiniNotationPreview.swift",
        "SurVibe/Songs/FilterChip.swift",
        "SurVibe/Songs/SongDetailView.swift",
        "SurVibe/Songs/SongImportSheet.swift",
        "SurVibe/Songs/SongLibraryView.swift",
        "SurVibe/Songs/PlaybackControlsView.swift",
        "SurVibe/Songs/LanguageBadge.swift",
        // Onboarding (6)
        "SurVibe/Onboarding/SkillLevelView.swift",
        "SurVibe/Onboarding/PostOnboardingWelcomeView.swift",
        "SurVibe/Onboarding/OnboardingLanguageView.swift",
        "SurVibe/Onboarding/OnboardingContainerView.swift",
        "SurVibe/Onboarding/NotationPreferenceView.swift",
        "SurVibe/Onboarding/DoorSelectorView.swift",
        // Components (1)
        "SurVibe/Components/DoorCard.swift",
        // PlayAlong Results (1)
        "SurVibe/PlayAlong/PlayAlongResultsOverlay.swift",
        // Practice (1 — latency-conservative)
        "SurVibe/Practice/PitchProximityMeter.swift"
    ]

    private static let latencyConservativeFiles: [String] = [
        "SurVibe/Practice/PitchProximityMeter.swift"
    ]

    // MARK: - Banned patterns

    private static let bannedPatterns: [String] = [
        #"Color\(\.secondarySystemBackground\)"#,
        #"Color\(\.tertiarySystemBackground\)"#,
        #"Color\(\.systemGray[0-9]?\)"#,
        #"\.foregroundStyle\(\.green\)"#,
        #"\.foregroundStyle\(\.red\)"#,
        #"\.foregroundStyle\(\.purple\)"#,
        #"\.foregroundStyle\(\.orange\)"#,
        #"\.tint\(\.green\)"#,
        #"\.tint\(\.pink\)"#,
        #"\.tint\(\.purple\)"#,
        #"\.tint\(\.orange\)"#
    ]

    // MARK: - Helpers

    /// Project root derived from this file's path so the test works from any
    /// worktree (`#filePath` resolves to the actual on-disk location of the
    /// test source file at compile time).
    private static let projectRoot: String = {
        let testFile = URL(fileURLWithPath: #filePath)
        // SurVibeTests/CrossAppThemeContractTests.swift → up 2 levels = project root
        return testFile.deletingLastPathComponent().deletingLastPathComponent().path
    }()

    /// Load a file and strip comment-only lines so `///` doc comments mentioning
    /// banned patterns don't false-positive.
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

    /// Contract: No cross-app refactored file contains banned color hardcodes.
    @Test func noCrossAppFileContainsBannedColorHardcodes() throws {
        for path in Self.crossAppFiles {
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

    /// Contract: PitchProximityMeter is high-mutation-frequency (called at
    /// ~20-40 Hz from pitch detection updates). It MUST NOT read
    /// `@Environment(AppThemeManager.self)`. Theme colors arrive as `let`
    /// params from `SongPlayAlongView+Subviews`.
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
