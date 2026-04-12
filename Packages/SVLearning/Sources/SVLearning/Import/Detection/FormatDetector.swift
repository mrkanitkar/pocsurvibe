import Foundation
import os

private let formatDetectorLogger = Logger.survibe(category: "FormatDetector")

/// Detects the notation format of a raw text input.
///
/// Uses a heuristic scoring approach — each format accumulates evidence points
/// from keyword matches, structural patterns, and filename hints.
/// The format with the highest score above the minimum threshold wins.
/// Returns `.unknown` if no format reaches the threshold.
public struct FormatDetector: Sendable {

    // MARK: - Constants

    /// Minimum score required to claim a format detection.
    private static let minimumScore: Int = 2

    // MARK: - Public Methods

    /// Detects the most likely notation format for the given input.
    ///
    /// - Parameter input: The raw notation input to inspect.
    /// - Returns: The detected `NotationInput.Format`, or `.unknown` if inconclusive.
    public func detect(_ input: NotationInput) -> NotationInput.Format {
        // If the caller declared a format (not .unknown), trust it
        if input.declaredFormat != .unknown {
            return input.declaredFormat
        }

        // Check filename hint first — strongest signal
        if let hint = input.filenameHint?.lowercased() {
            if hint.hasSuffix(".xml") || hint.hasSuffix(".mxl") || hint.hasSuffix(".musicxml") {
                return .musicXML
            }
        }

        let text = input.text

        // Score each format
        let musicXMLScore = scoreMusicXML(text)
        let sargamScore = scoreSargam(text)
        let westernScore = scoreWestern(text)

        // Find the winner
        let scores: [(NotationInput.Format, Int)] = [
            (.musicXML, musicXMLScore),
            (.sargam, sargamScore),
            (.western, westernScore),
        ]

        guard let best = scores.max(by: { $0.1 < $1.1 }), best.1 >= Self.minimumScore else {
            formatDetectorLogger.info("Format detection inconclusive, returning unknown")
            return .unknown
        }

        formatDetectorLogger.info(
            "Detected format \(String(describing: best.0), privacy: .public) with score \(best.1, privacy: .public)"
        )

        return best.0
    }

    // MARK: - Private Scoring

    /// Scores text for MusicXML format evidence.
    ///
    /// MusicXML has distinctive XML tags that are highly specific.
    private func scoreMusicXML(_ text: String) -> Int {
        var score = 0
        let markers = ["<score-partwise", "<score-timewise", "<part-list", "<measure", "<note>", "<pitch>", "<?xml"]
        for marker in markers where text.contains(marker) {
            score += 3
        }
        return score
    }

    /// Scores text for Sargam notation format evidence.
    ///
    /// Sargam uses Indian note names (Sa, Re, Ga, Ma, Pa, Dha, Ni)
    /// and modifiers (Komal, Tivra, lowercase k/t prefix).
    private func scoreSargam(_ text: String) -> Int {
        var score = 0

        // Core sargam syllables (case-insensitive word boundary check)
        let sargamNotes = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"]
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if sargamNotes.contains(where: { cleaned.caseInsensitiveCompare($0) == .orderedSame }) {
                score += 1
            }
        }

        // Modifier keywords
        if text.localizedCaseInsensitiveContains("komal") { score += 3 }
        if text.localizedCaseInsensitiveContains("tivra") { score += 3 }
        if text.localizedCaseInsensitiveContains("sargam") { score += 2 }

        // Devanagari characters — strong sargam signal
        if text.unicodeScalars.contains(where: { $0.value >= 0x0900 && $0.value <= 0x097F }) {
            score += 4
        }

        return score
    }

    /// Scores text for Western notation format evidence.
    ///
    /// Western notation uses letter names (C–B) with octave numbers,
    /// accidentals (#, b), and duration markers.
    private func scoreWestern(_ text: String) -> Int {
        var score = 0

        // Western note pattern: letter + optional accidental + octave number (e.g. C4, D#3, Eb5)
        let westernPattern = try? NSRegularExpression(pattern: "\\b[A-Ga-g][#b]?[0-9]\\b")
        let range = NSRange(text.startIndex..., in: text)
        let matchCount = westernPattern?.numberOfMatches(in: text, range: range) ?? 0
        score += min(matchCount * 2, 10) // Cap at 10 to avoid runaway scoring

        // Duration markers
        let durationMarkers = ["quarter", "half", "whole", "eighth", "16th", "dotted"]
        for marker in durationMarkers where text.localizedCaseInsensitiveContains(marker) {
            score += 1
        }

        // Key signature markers
        if text.localizedCaseInsensitiveContains("major") || text.localizedCaseInsensitiveContains("minor") {
            score += 2
        }

        return score
    }
}
