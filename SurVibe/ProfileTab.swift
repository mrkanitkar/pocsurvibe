import SVCore
import SwiftUI

/// Profile tab — user profile, authentication, and app settings.
///
/// Shows authentication state at the top (sign in button or user info),
/// followed by settings (language, redo onboarding).
struct ProfileTab: View {
    // MARK: - Properties

    @State private var languageManager = LanguageManager()
    @Environment(AuthManager.self) private var authManager
    @Environment(OnboardingManager.self) private var onboardingManager

    /// Controls the sign-in prompt sheet.
    @State private var signInTrigger: SignInTrigger?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                authSection
                settingsSection
            }
            .navigationTitle("Profile")
            .navigationDestination(for: String.self) { destination in
                if destination == "languages" {
                    LanguageSelectorView()
                }
            }
            .sheet(item: $signInTrigger) { trigger in
                SignInPromptView(trigger: trigger)
            }
        }
        .accessibilityLabel(AccessibilityHelper.tabLabel(for: "Profile"))
    }

    // MARK: - Sections

    /// Authentication section — shows user info when signed in, or sign-in button when anonymous.
    private var authSection: some View {
        Section {
            if authManager.isAuthenticated {
                // Signed-in state
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        if let user = authManager.currentUser {
                            if !user.displayName.isEmpty {
                                Text(verbatim: user.displayName)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            } else {
                                Text("SurVibe User")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                            }

                            if let email = user.email {
                                Text(verbatim: email)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("Signed in with Apple")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)

                // Sign Out button
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.forward")
                }
                .accessibilityLabel(Text("Sign Out"))
                .accessibilityHint(Text("Double tap to sign out of your Apple ID"))
            } else {
                // Anonymous state
                HStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not Signed In")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Sign in to sync progress and access premium content")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)

                // Sign In button
                Button {
                    signInTrigger = .profile
                } label: {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                }
                .accessibilityLabel(Text("Sign in with Apple"))
                .accessibilityHint(Text("Double tap to sign in with your Apple ID"))
            }
        }
    }

    /// User preference for auto-hiding sargam labels as accuracy improves.
    @AppStorage("autoHideSargamLabels") private var autoHideSargamLabels: Bool = true

    /// Settings section — language selector, sargam label toggle, and redo onboarding.
    private var settingsSection: some View {
        Section(header: Text("Settings")) {
            NavigationLink(value: "languages") {
                HStack {
                    Label("App Language", systemImage: "globe")
                    Spacer()
                    Text(verbatim: languageManager.currentLanguageDisplayName)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel(Text("App Language"))
            .accessibilityHint(
                Text("Current language: \(languageManager.currentLanguageDisplayName). Double tap to change.")
            )

            // Auto-hide sargam labels toggle
            Toggle("Auto-hide sargam labels", isOn: $autoHideSargamLabels)
                .accessibilityLabel("Auto-hide sargam labels")
                .accessibilityHint("When enabled, sargam labels fade as your accuracy improves")

            // Redo Onboarding
            Button {
                onboardingManager.resetOnboarding()
            } label: {
                Label("Redo Onboarding", systemImage: "arrow.counterclockwise")
            }
            .accessibilityLabel(Text("Redo Onboarding"))
            .accessibilityHint(Text("Double tap to restart the onboarding flow and reconfigure your preferences"))
        }
    }
}

#Preview {
    ProfileTab()
        .environment(AuthManager.shared)
        .environment(OnboardingManager())
}
