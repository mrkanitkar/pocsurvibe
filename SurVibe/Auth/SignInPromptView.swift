import SVCore
import SwiftUI

/// A sheet view that prompts the user to sign in with Apple.
///
/// Displays context-specific messaging based on the `SignInTrigger` that initiated
/// the prompt (e.g., premium song access, cloud sync, profile). Includes the
/// system `SignInWithAppleButton`, a "Not now" dismiss option, loading state
/// during authentication, and error display on failure.
///
/// Present as a sheet from any view that requires authentication:
/// ```swift
/// .sheet(item: $signInTrigger) { trigger in
///     SignInPromptView(trigger: trigger)
/// }
/// ```
struct SignInPromptView: View {
    // MARK: - Properties

    /// The context that triggered this sign-in prompt.
    let trigger: SignInTrigger

    /// Dismiss action for closing the sheet.
    @Environment(\.dismiss) private var dismiss

    /// The shared auth manager injected via the environment.
    @Environment(AuthManager.self) private var authManager

    /// Tracks whether a sign-in request is currently in progress.
    @State private var isLoading = false

    /// Holds the error message to display when sign-in fails.
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // App icon or decorative image
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                // Trigger-specific title
                Text(trigger.promptTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                // Trigger-specific message
                Text(trigger.promptMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                // Error message display
                if let errorMessage {
                    Label {
                        Text(errorMessage)
                            .font(.callout)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(
                        Text("Error: \(errorMessage)")
                    )
                }

                // Sign in with Apple button or loading indicator
                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(height: 50)
                        .accessibilityLabel(
                            Text("Signing in")
                        )
                        .accessibilityValue(
                            Text("Please wait while we sign you in")
                        )
                } else {
                    Button {
                        performSignIn()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "apple.logo")
                                .font(.title3)
                                .accessibilityHidden(true)
                            Text("Sign in with Apple")
                                .font(.body.weight(.medium))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: 280)
                        .frame(height: 50)
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .accessibilityLabel(
                        Text("Sign in with Apple")
                    )
                    .accessibilityHint(
                        Text("Double tap to sign in with your Apple ID")
                    )
                }

                // Not now button
                Button {
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("Not now"))
                .accessibilityHint(
                    Text("Double tap to dismiss the sign in prompt")
                )
                .padding(.top, 8)
                .disabled(isLoading)

                Spacer()
                    .frame(height: 32)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(Text("Close"))
                    .accessibilityHint(
                        Text("Double tap to dismiss the sign in prompt")
                    )
                    .disabled(isLoading)
                }
            }
        }
        .interactiveDismissDisabled(isLoading)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Private Methods

    /// Performs the Sign in with Apple flow via `AuthManager`.
    ///
    /// Sets the loading state, calls `signInWithApple()`, and handles
    /// success (dismiss), cancellation (dismiss), or error (display message).
    private func performSignIn() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                _ = try await authManager.signInWithApple()
                dismiss()
            } catch let error as AuthError {
                switch error {
                case .cancelled:
                    // User cancelled — just dismiss without showing error
                    dismiss()
                default:
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview("Profile Trigger") {
    SignInPromptView(trigger: .profile)
        .environment(AuthManager.shared)
}

#Preview("Premium Song Trigger") {
    SignInPromptView(trigger: .premiumSong)
        .environment(AuthManager.shared)
}
