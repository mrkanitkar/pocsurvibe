import SVCore
import SwiftUI

/// Branded in-app explanation shown BEFORE the system microphone permission
/// alert. Gated by `@AppStorage("hasSeenMicPermissionPrePrompt")` so the
/// pre-prompt only appears on the user's first play-along session.
///
/// Users who dismiss or confirm this sheet will not see it again; the
/// subsequent call to `PermissionManager.shared.requestMicrophoneAccess()`
/// in the play-along load flow then triggers the system alert.
///
/// TODO(SP-5): migrate `hasSeenMicPermissionPrePrompt` from `@AppStorage`
/// to a `PreferenceStoring` concrete implementer.
struct MicPermissionPrePrompt: View {
    // MARK: - Properties

    @AppStorage("hasSeenMicPermissionPrePrompt")
    private var hasSeen: Bool = false

    /// Two-way binding to the parent's presentation flag. Tapping Continue
    /// flips this to `false`, which is the reliable way to dismiss a
    /// `.sheet(isPresented:)` — `@Environment(\.dismiss)` was previously
    /// observed to silently no-op on iPad in iOS 26 with this presentation
    /// detent. Driving the binding directly removes that ambiguity.
    @Binding var isPresented: Bool

    /// Invoked after the user confirms — callers may use this to kick off
    /// the system permission request, log telemetry, etc. Safe to pass an
    /// empty closure when the permission flow is issued independently.
    let onContinue: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.rangNeel)
                .accessibilityHidden(true)

            Text("Microphone access")
                .font(.title2.weight(.semibold))

            Text(
                "SurVibe listens to your singing or playing to score your pitch in real time. "
                    + "Your audio is processed on-device only — nothing is recorded or uploaded."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal)

            Button {
                hasSeen = true
                isPresented = false
                onContinue()
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .accessibilityHint("Dismisses the rationale and proceeds to play-along.")
        }
        .padding(.vertical, 32)
        .presentationDetents([.medium])
    }

    // MARK: - Static helpers

    /// Whether the pre-prompt should still be shown for this user.
    ///
    /// Reads the `hasSeenMicPermissionPrePrompt` flag directly from
    /// `UserDefaults` so call sites can gate sheet presentation without
    /// owning an `@AppStorage` binding themselves.
    static var shouldShow: Bool {
        !UserDefaults.standard.bool(forKey: "hasSeenMicPermissionPrePrompt")
    }
}

// MARK: - Preview

#Preview {
    MicPermissionPrePrompt(isPresented: .constant(true), onContinue: {})
}
