import SVCore
import SwiftUI

/// A small badge displaying a song's difficulty level with color coding.
///
/// Maps the integer difficulty (1–5) to a human-readable label and
/// a color from the Rang color system (Neel → Sona) via `RangLevel`.
/// Badge text color is resolved through `AppThemeManager` to ensure
/// legibility across all themes and dark-mode variants.
///
/// Usage:
/// ```swift
/// DifficultyBadge(difficulty: song.difficulty)
/// ```
struct DifficultyBadge: View {
    // MARK: - Properties

    /// The difficulty level (1–5).
    let difficulty: Int

    @Environment(AppThemeManager.self) private var themeManager

    // MARK: - Body

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(themeManager.resolved.badgeTextColor)
            .background(
                Capsule()
                    .fill(color)
            )
            .accessibilityLabel(Text("Difficulty: \(label)"))
    }

    // MARK: - Private Methods

    /// Human-readable label for the difficulty level.
    private var label: String {
        switch difficulty {
        case 1: "Beginner"
        case 2: "Easy"
        case 3: "Medium"
        case 4: "Hard"
        case 5: "Expert"
        default: "Level \(difficulty)"
        }
    }

    /// Capsule background color for the difficulty badge.
    ///
    /// Resolved via `RangLevel` so colors stay in sync with the canonical
    /// Rang color system in SVCore. Falls back to `.gray` for out-of-range values.
    private var color: Color {
        RangLevel(rawValue: difficulty)?.color ?? .gray
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 8) {
        ForEach(1...5, id: \.self) { level in
            DifficultyBadge(difficulty: level)
        }
    }
    .padding()
    .environment(AppThemeManager())
}
