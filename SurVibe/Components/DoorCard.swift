import SVCore
import SwiftUI

/// A reusable card component representing a "Door" on the Home tab.
///
/// Each door is a tappable card with an icon, title, subtitle, and gradient background.
/// Doors can be enabled (navigable) or disabled (showing a "Coming Soon" badge).
/// The card supports Dynamic Type, VoiceOver, and reduced-motion preferences.
///
/// ## Usage
/// ```swift
/// DoorCard(
///     icon: "music.note",
///     title: "Songs",
///     subtitle: "Explore melodies",
///     gradientColors: [.rangNeel, .rangNeel.opacity(0.7)],
///     isEnabled: true
/// ) {
///     router.switchTab(to: .songs)
/// }
/// ```
struct DoorCard: View {
    // MARK: - Properties

    /// SF Symbol name displayed at the top of the card.
    let icon: String

    /// Primary title displayed below the icon.
    let title: String

    /// Descriptive subtitle displayed below the title.
    let subtitle: String

    /// Gradient colors for the card background, from top-leading to bottom-trailing.
    let gradientColors: [Color]

    /// Whether the door is tappable. Disabled doors show a "Coming Soon" badge.
    let isEnabled: Bool

    /// Action to perform when the enabled card is tapped.
    let action: () -> Void

    /// Theme manager providing resolved semantic colors for the current theme.
    @Environment(AppThemeManager.self)
    private var themeManager

    /// User preference for reduced motion animations.
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// Tracks whether the card is currently being pressed for visual feedback.
    @State
    private var isPressed = false

    // MARK: - Body

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(themeManager.resolved.badgeTextColor)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(themeManager.resolved.badgeTextColor)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(themeManager.resolved.badgeTextColor.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 12)
            .background(
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
                if !isEnabled {
                    comingSoonBadge
                }
            }
            .opacity(isEnabled ? 1.0 : 0.6)
            .blur(radius: isEnabled ? 0 : 1)
            .scaleEffect(isPressed && !reduceMotion ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .hoverEffect(.automatic, isEnabled: isEnabled)
        .disabled(!isEnabled)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(
            isEnabled
                ? "Double tap to explore \(title)"
                : "Coming soon. Not yet available."
        )
        .accessibilityAddTraits(.isButton)
        .if(!isEnabled) { view in
            view.accessibilityAddTraits(.isStaticText)
        }
    }

    // MARK: - Private Views

    /// "Coming Soon" badge overlay shown on disabled cards.
    private var comingSoonBadge: some View {
        Text("Coming Soon")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(themeManager.resolved.badgeTextColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .padding(8)
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("DoorCard — Enabled") {
    DoorCard(
        icon: "music.note",
        title: "Songs",
        subtitle: "Explore melodies from Indian cinema",
        gradientColors: [.rangNeel, Color(red: 0.18, green: 0.22, blue: 0.55)],  // brand-darker companion to rangNeel
        isEnabled: true
    ) {
        // preview action
    }
    .frame(width: 180)
    .padding()
}

#Preview("DoorCard — Disabled") {
    DoorCard(
        icon: "heart.fill",
        title: "Moods",
        subtitle: "Play by emotion",
        gradientColors: [.rangLal, Color(red: 0.65, green: 0.12, blue: 0.12)],  // brand-darker companion to rangLal
        isEnabled: false
    ) {
        // preview action
    }
    .frame(width: 180)
    .padding()
}
