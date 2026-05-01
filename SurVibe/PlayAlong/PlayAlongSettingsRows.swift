import SwiftUI

// MARK: - DisclosureRow

/// A NavigationLink-style row showing a title, optional value preview, and
/// system chevron.
///
/// Used in the play-along settings sheet for drill-down selections such as
/// hand assignment, backing track, and key signature. The row combines its
/// children into a single accessibility element so VoiceOver announces
/// "Title, value" as one unit.
///
/// - Parameters:
///   - title: Leading label text.
///   - value: Optional secondary text shown trailing before the chevron.
///   - destination: View pushed onto the navigation stack on tap.
struct DisclosureRow<Destination: View>: View {
    let title: String
    let value: String?
    let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(title)
                Spacer()
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Double tap to change")
        }
    }
}

// MARK: - ToggleRow

/// A toggle switch with a text label and optional accessibility hint.
///
/// Provides a consistent row style for boolean settings such as wait mode
/// and metronome on/off. When `hint` is nil the accessibility hint is
/// omitted, so VoiceOver reads only the label and on/off state.
struct ToggleRow: View {
    /// Label displayed next to the toggle.
    let title: String

    /// Two-way binding to the boolean value controlled by this toggle.
    @Binding var isOn: Bool

    /// Optional VoiceOver hint describing what the toggle does.
    var hint: String?

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
        }
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
    }
}

// MARK: - SegmentedRow

/// A labelled segmented picker for small option sets.
///
/// Renders a secondary-style section title above an inline segmented
/// `Picker`. The generic `T` must be `Hashable` and `Identifiable` so
/// SwiftUI can tag and iterate options.
///
/// - Parameters:
///   - title: Descriptive label shown above the picker.
///   - options: The set of selectable values.
///   - selection: Two-way binding to the currently selected value.
///   - label: Closure that converts a value to its display string.
struct SegmentedRow<T: Hashable & Identifiable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(label(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(title)
            .accessibilityHint("Select an option")
        }
    }
}

// MARK: - ActionRow

/// A tappable button row with a leading SF Symbol icon.
///
/// Used for discrete actions inside the settings sheet such as
/// "Reset to Defaults" or "Export MIDI". The button respects the
/// `isEnabled` flag to grey out when unavailable.
struct ActionRow: View {
    /// Button label text.
    let title: String

    /// SF Symbol name for the leading icon.
    let systemImage: String

    /// Whether the button is interactive. When `false` the row appears
    /// dimmed and taps are ignored.
    let isEnabled: Bool

    /// Closure invoked on tap.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
                Text(title)
            }
        }
        .disabled(!isEnabled)
        .accessibilityLabel(title)
        .accessibilityHint(isEnabled ? "Double tap to activate" : "Currently unavailable")
    }
}

// MARK: - ChipRow

/// A read-only row displaying a title and a horizontal strip of badge chips.
///
/// Used to show metadata such as active features, raga tags, or skill
/// labels. Each chip renders as a capsule with secondary background.
/// Chips are purely informational and not interactive, so VoiceOver
/// combines them into a single announcement.
struct ChipRow: View {
    /// Section title shown above the chips.
    let title: String

    /// Display strings rendered as individual capsule badges.
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(badges.joined(separator: ", "))")
        }
    }
}
