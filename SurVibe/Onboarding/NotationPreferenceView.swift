import os
import SVCore
import SwiftUI

/// Onboarding screen 2: notation display preference.
///
/// Presents three selectable cards (Sargam, Western, Dual) each with a
/// mini preview of what the notation looks like. The selection is stored
/// in `OnboardingManager.notationPreference` and later propagated to the
/// notation rendering engine.
///
/// Navigation chrome (Next / Back / Skip) is handled by the parent
/// container — this view only manages the notation preference state.
struct NotationPreferenceView: View {
    // MARK: - Logger

    private static let logger = Logger.survibe(category: "OnboardingNotation")

    // MARK: - Properties

    @Environment(OnboardingManager.self) private var onboardingManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            VStack(spacing: 16) {
                ForEach(NotationDisplayMode.allCases, id: \.self) { mode in
                    notationCard(for: mode)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 32)
        .onAppear { Self.logger.info("Onboarding screen appeared: NotationPreference") }
    }

    // MARK: - Subviews

    /// Title and subtitle for the notation preference screen.
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Choose your notation")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("You can change this anytime in Settings")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    /// A selectable card showing a notation mode with a live preview.
    ///
    /// - Parameter mode: The notation display mode this card represents.
    /// - Returns: A styled card with title, preview, and selection indicator.
    private func notationCard(for mode: NotationDisplayMode) -> some View {
        let isSelected = onboardingManager.notationPreference == mode
        let fillColor: Color = isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground)
        let strokeColor: Color = isSelected ? Color.accentColor : .clear

        return Button {
            if reduceMotion {
                onboardingManager.notationPreference = mode
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    onboardingManager.notationPreference = mode
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(verbatim: mode.label)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }

                notationPreview(for: mode)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(strokeColor, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notationAccessibilityLabel(for: mode))
        .accessibilityHint(isSelected ? Text("Currently selected") : Text("Double tap to select"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Mini preview showing what the notation looks like for each mode.
    ///
    /// - Parameter mode: The notation display mode to preview.
    /// - Returns: Styled text showing sample note names.
    private func notationPreview(for mode: NotationDisplayMode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch mode {
            case .sargam:
                sargamPreviewLine

            case .western:
                westernPreviewLine

            case .dual:
                sargamPreviewLine
                westernPreviewLine

            case .sheetMusic:
                sheetMusicPreviewLine

            case .sargamPlusSheet:
                sargamPreviewLine
                sheetMusicPreviewLine
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    /// Sargam notation preview text.
    private var sargamPreviewLine: some View {
        Text(verbatim: "Sa  Re  Ga  Ma  Pa")
            .font(.system(.body, design: .monospaced))
            .fontWeight(.medium)
            .foregroundStyle(.primary)
    }

    /// Western notation preview text.
    private var westernPreviewLine: some View {
        Text(verbatim: "C    D    E    F    G")
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    /// Sheet music preview showing a 5-line staff icon.
    private var sheetMusicPreviewLine: some View {
        HStack(spacing: 4) {
            Image(systemName: "music.note.list")
                .font(.body)
                .foregroundStyle(.secondary)
            Text(verbatim: "5-line staff notation")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Private Methods

    /// Build the accessibility label for a notation card.
    ///
    /// - Parameter mode: The notation display mode.
    /// - Returns: A descriptive label including what the notation shows.
    private func notationAccessibilityLabel(for mode: NotationDisplayMode) -> Text {
        switch mode {
        case .sargam:
            return Text("Sargam notation. Shows Indian classical note names: Sa, Re, Ga, Ma, Pa, Dha, Ni")
        case .western:
            return Text("Western notation. Shows standard note names: C, D, E, F, G, A, B")
        case .dual:
            return Text("Dual notation. Shows both Sargam and Western note names together")
        case .sheetMusic:
            return Text("Sheet music. Shows standard 5-line staff notation with treble clef")
        case .sargamPlusSheet:
            return Text("Sargam plus sheet music. Shows Sargam note names above a 5-line staff")
        }
    }
}

// MARK: - Preview

#Preview {
    NotationPreferenceView()
        .environment(OnboardingManager())
}
