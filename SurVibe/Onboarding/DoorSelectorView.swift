import os
import SVCore
import SwiftUI

/// Onboarding screen 1: feature door selection.
///
/// Presents a grid of 5 feature areas (Songs, Learn, Moods, Community, Practice)
/// from which the user picks 1 to 3 interests. The selection personalizes the
/// home screen layout.
///
/// Navigation chrome (Next / Back / Skip) is handled by the parent
/// container — this view only manages the door selection state.
struct DoorSelectorView: View {
    // MARK: - Logger

    private static let logger = Logger.survibe(category: "OnboardingDoorSelector")

    // MARK: - Properties

    @Environment(OnboardingManager.self) private var onboardingManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Two-column adaptive grid layout for door cards.
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    /// Maximum number of doors a user can select.
    private let maxSelections = 3

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            selectionCounter

            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(OnboardingDoorType.allCases, id: \.self) { door in
                        doorCard(for: door)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding(.top, 32)
        .onAppear { Self.logger.info("Onboarding screen appeared: DoorSelector") }
    }

    // MARK: - Subviews

    /// Title and subtitle for the door selection screen.
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("What interests you?")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Pick up to 3 to customize your experience")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    /// Displays the current selection count out of the maximum.
    private var selectionCounter: some View {
        Text("\(onboardingManager.preferredDoors.count) of \(maxSelections) selected")
            .font(.footnote)
            .fontWeight(.medium)
            .foregroundStyle(
                onboardingManager.preferredDoors.isEmpty ? .red : .secondary
            )
            .accessibilityLabel(
                Text("\(onboardingManager.preferredDoors.count) of \(maxSelections) interests selected")
            )
    }

    /// A selectable card representing a single feature door.
    ///
    /// Toggles the door in or out of the user's selection set.
    /// Selection is disabled when 3 doors are already chosen (unless
    /// toggling off an already-selected door).
    ///
    /// - Parameter door: The door type this card represents.
    /// - Returns: A styled card view with icon, label, and subtitle.
    private func doorCard(for door: OnboardingDoorType) -> some View {
        let isSelected = onboardingManager.preferredDoors.contains(door)
        let isAtLimit = onboardingManager.preferredDoors.count >= maxSelections
        let isDisabled = !isSelected && isAtLimit
        let fillColor: Color = isSelected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground)
        let strokeColor: Color = isSelected ? Color.accentColor : .clear
        let iconForeground: Color = isSelected ? .white : isDisabled ? Color.gray : Color.accentColor
        let iconBackground: Color = isSelected
            ? Color.accentColor
            : isDisabled ? Color(.tertiarySystemFill) : Color.accentColor.opacity(0.12)

        return Button {
            toggleDoor(door)
        } label: {
            doorCardLabel(
                door: door,
                isDisabled: isDisabled,
                iconForeground: iconForeground,
                iconBackground: iconBackground
            )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 14).fill(fillColor))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(strokeColor, lineWidth: 2))
                .opacity(isDisabled ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(Text(verbatim: "\(door.label). \(door.subtitle)"))
        .accessibilityHint(doorHint(isSelected: isSelected, isDisabled: isDisabled))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Label content for a door card, extracted to help the compiler type-check.
    ///
    /// - Parameters:
    ///   - door: The door type to display.
    ///   - isDisabled: Whether the card is disabled due to max selections.
    ///   - iconForeground: Foreground color for the icon.
    ///   - iconBackground: Background color for the icon circle.
    /// - Returns: The card's interior layout.
    private func doorCardLabel(
        door: OnboardingDoorType,
        isDisabled: Bool,
        iconForeground: Color,
        iconBackground: Color
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: door.icon)
                .font(.largeTitle)
                .foregroundStyle(iconForeground)
                .frame(width: 56, height: 56)
                .background(iconBackground)
                .clipShape(Circle())

            VStack(spacing: 4) {
                Text(verbatim: door.label)
                    .font(.headline)
                    .foregroundStyle(isDisabled ? .secondary : .primary)

                Text(verbatim: door.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Private Methods

    /// Toggle a door in or out of the selected set with optional animation.
    ///
    /// - Parameter door: The door to toggle.
    private func toggleDoor(_ door: OnboardingDoorType) {
        let action = {
            if onboardingManager.preferredDoors.contains(door) {
                onboardingManager.preferredDoors.remove(door)
            } else if onboardingManager.preferredDoors.count < maxSelections {
                onboardingManager.preferredDoors.insert(door)
            }
        }

        if reduceMotion {
            action()
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                action()
            }
        }
    }

    /// Build the accessibility hint for a door card.
    ///
    /// - Parameters:
    ///   - isSelected: Whether the door is currently selected.
    ///   - isDisabled: Whether the door is disabled due to max selections.
    /// - Returns: Contextual hint text.
    private func doorHint(isSelected: Bool, isDisabled: Bool) -> Text {
        if isSelected {
            return Text("Double tap to deselect")
        } else if isDisabled {
            return Text("Maximum selections reached. Deselect another to choose this one.")
        } else {
            return Text("Double tap to select")
        }
    }
}

// MARK: - Preview

#Preview {
    DoorSelectorView()
        .environment(OnboardingManager())
}
