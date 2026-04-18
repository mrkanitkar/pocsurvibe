import Foundation
import Testing

/// Static-source latency-contract guard.
///
/// The design spec locks an inviolable rule: performance-critical views must
/// NEVER read `@Environment(AppThemeManager.self)` — doing so triggers
/// 60–120 Hz re-renders from the CADisplayLink highlight path and blows the
/// 3–10 ms audio latency guarantee.
///
/// This test greps the source files at test time. It strips comment-only lines
/// (lines whose first non-whitespace character is `/` followed by `/`) before
/// searching, so documentation that *mentions* the forbidden pattern (to
/// explain why it is forbidden) does not trigger a false positive.
struct LatencyContractTests {
    @Test func performanceCriticalViewsDoNotReadThemeEnvironment() throws {
        let filesToCheck = [
            "SurVibe/PlayAlong/FallingNotesView.swift",
            "SurVibe/PlayAlong/Notation/BarsOnStaffView.swift",
            "SurVibe/PlayAlong/Notation/SargamDualRowView.swift",
            "SurVibe/PlayAlong/Notation/SplitLaneView.swift",
            "SurVibe/PlayAlong/ScrollingSheetView.swift",
            "SurVibe/Audio/InteractivePianoView.swift"
        ]
        // Derive project root from this file's path so the test works from any
        // worktree (`#filePath` resolves to the actual on-disk location of the
        // test source file at compile time).
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile.deletingLastPathComponent().deletingLastPathComponent().path
        let forbiddenPattern = "@Environment(AppThemeManager.self)"

        for file in filesToCheck {
            let path = "\(projectRoot)/\(file)"
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                continue  // File may not exist in some branches; soft-skip
            }
            // Drop any line whose first non-whitespace characters are `//` — comments,
            // including /// doc comments, cannot violate the contract.
            let codeOnly = content
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { line in
                    let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                    return !trimmed.hasPrefix("//")
                }
                .joined(separator: "\n")

            #expect(
                !codeOnly.contains(forbiddenPattern),
                "VIOLATION: \(file) reads theme via @Environment — must use let parameters per latency contract"
            )
        }
    }
}
