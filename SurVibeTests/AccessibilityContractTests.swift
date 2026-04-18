import Foundation
import Testing

/// Static-source accessibility contract guard.
///
/// Asserts SwiftUI views in `SurVibe/` honour accessibility patterns:
/// - Every `Image(systemName:)` has an `.accessibilityLabel`, `.accessibilityHidden`, or
///   parent `Label(` / `.accessibilityElement` within 5 lines below.
/// - Every file that calls `withAnimation(` also references `reduceMotion` or
///   `accessibilityReduceMotion` (file-level heuristic).
///
/// Mirrors the `LearnTabThemeContractTests` / `CrossAppThemeContractTests` pattern.
/// Comment-only lines are stripped before searching so `///` doc comments
/// mentioning patterns don't trigger false positives.
struct AccessibilityContractTests {

    private static let projectRoot = "/Users/maheshwar/Developer/SurVibe"

    // MARK: - Exemptions

    /// Files exempt from the icon-label check (e.g., notation renderers where
    /// icons are pure visual glyphs not announced by VoiceOver).
    private static let iconCheckExemptFiles: Set<String> = [
        // Add file paths (relative to projectRoot) here if false positives need silencing.
    ]

    /// Files exempt from the reduce-motion check (e.g., models or services
    /// that legitimately can't read environment values).
    private static let motionCheckExemptFiles: Set<String> = [
        // Add file paths (relative to projectRoot) here if false positives need silencing.
    ]

    // MARK: - Helpers

    private static func swiftFiles(in directory: String) -> [String] {
        let url = URL(fileURLWithPath: "\(projectRoot)/\(directory)")
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: nil
        ) else { return [] }
        var result: [String] = []
        for case let fileURL as URL in enumerator
            where fileURL.pathExtension == "swift" {
            let relative = String(fileURL.path.dropFirst(projectRoot.count + 1))
            result.append(relative)
        }
        return result.sorted()
    }

    /// Returns source with comment-only lines removed so `///` doc comments
    /// mentioning banned patterns don't cause false positives.
    private static func codeOnly(for path: String) -> String? {
        let full = "\(projectRoot)/\(path)"
        guard let content = try? String(contentsOfFile: full, encoding: .utf8) else {
            return nil
        }
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
                return !trimmed.hasPrefix("//")
            }
            .joined(separator: "\n")
    }

    // MARK: - Contract Tests

    /// Every `Image(systemName:)` must be followed within 5 lines by
    /// `.accessibilityLabel`, `.accessibilityHidden`, a parent `Label(`, or
    /// `.accessibilityElement` — ensuring VoiceOver has the right information.
    @Test func everyIconIsLabeledOrHidden() throws {
        var violations: [String] = []
        for path in Self.swiftFiles(in: "SurVibe")
            where !Self.iconCheckExemptFiles.contains(path) {
            guard let code = Self.codeOnly(for: path) else { continue }
            let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            for (idx, line) in lines.enumerated() where line.contains("Image(systemName:") {
                let windowEnd = min(idx + 6, lines.count)
                let window = lines[idx..<windowEnd].joined(separator: "\n")
                let hasLabel = window.contains(".accessibilityLabel")
                let hasHidden = window.contains(".accessibilityHidden")
                let hasParentLabel = window.contains("Label(")
                let hasElement = window.contains(".accessibilityElement")
                if !(hasLabel || hasHidden || hasParentLabel || hasElement) {
                    violations.append("\(path):\(idx + 1) — Image(systemName:) without accessibilityLabel/accessibilityHidden/parent Label within 5 lines")
                }
            }
        }
        #expect(violations.isEmpty, "\(violations.count) violation(s):\n\(violations.joined(separator: "\n"))")
    }

    /// Every file that calls `withAnimation(` must also reference `reduceMotion`
    /// or `accessibilityReduceMotion` somewhere in the file.
    ///
    /// This is a file-level heuristic — it catches gross omissions such as adding
    /// animation to a new view without wiring `@Environment(\.accessibilityReduceMotion)`.
    /// Per-call-site precision is enforced in code review.
    @Test func filesWithAnimationsReferenceReduceMotion() throws {
        var violations: [String] = []
        for path in Self.swiftFiles(in: "SurVibe")
            where !Self.motionCheckExemptFiles.contains(path) {
            guard let code = Self.codeOnly(for: path) else { continue }
            guard code.contains("withAnimation(") else { continue }
            let referencesMotion = code.contains("reduceMotion")
                || code.contains("accessibilityReduceMotion")
            if !referencesMotion {
                violations.append(
                    "\(path) — uses withAnimation( but doesn't reference reduceMotion. " +
                    "Add @Environment(\\.accessibilityReduceMotion) and guard the call."
                )
            }
        }
        #expect(violations.isEmpty, "\(violations.count) violation(s):\n\(violations.joined(separator: "\n"))")
    }
}
