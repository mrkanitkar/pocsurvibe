import SVCore
import SwiftUI

/// Profile header displaying the user's avatar, display name, and rang badge.
///
/// Shown at the top of the ProfileTab List as a prominent identity section.
/// The avatar is a system icon placeholder; the rang badge uses the existing
/// `RangBadgeView` from the gamification system.
struct ProfileHeaderView: View {
    // MARK: - Properties

    /// The user's display name (from AuthManager or fallback "SurVibe User").
    let displayName: String

    /// The user's current rang level for the badge display.
    let rang: RangLevel

    // MARK: - Body

    var body: some View {
        HStack(spacing: 16) {
            avatar
            userInfo
            Spacer()
            RangBadgeView(rang: rang, scale: 0.85)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("\(displayName), \(rang.displayName) level \(rang.proficiencyLabel)")
        )
    }

    // MARK: - Subviews

    /// Circular avatar placeholder icon.
    private var avatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 52))
            .foregroundStyle(rang.color.gradient)
            .accessibilityHidden(true)
    }

    /// Name and subtitle stack.
    private var userInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: displayName)
                .font(.title3)
                .fontWeight(.semibold)

            Text("SurVibe learner")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    List {
        ProfileHeaderView(displayName: "Maheshwar", rang: .hara)
        ProfileHeaderView(displayName: "SurVibe User", rang: .neel)
    }
}
