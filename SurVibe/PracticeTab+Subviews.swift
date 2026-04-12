import SVAudio
import SVCore
import SwiftUI

// MARK: - Toolbar & Control Subviews

extension PracticeTab {
    /// Toggle between piano and isomorphic sargam keyboard layouts.
    var keyboardLayoutToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                keyboardLayout = keyboardLayout == .piano ? .isomorphic : .piano
            }
        } label: {
            Image(systemName: keyboardLayout.systemImage)
                .font(.title3)
        }
        .accessibilityLabel({
            let target = keyboardLayout == .piano
                ? KeyboardLayoutMode.isomorphic.displayName
                : KeyboardLayoutMode.piano.displayName
            return "Switch to \(target) layout"
        }())
        .accessibilityHint("Toggles between piano and sargam keyboard layouts")
    }

    /// Latching toggle and clear button for chord building mode.
    @ViewBuilder
    var latchingControls: some View {
        Button {
            isLatchingEnabled.toggle()
        } label: {
            Image(systemName: isLatchingEnabled ? "pin.fill" : "pin")
                .font(.title3)
                .foregroundStyle(isLatchingEnabled ? .green : .secondary)
        }
        .accessibilityLabel(isLatchingEnabled ? "Disable latching" : "Enable latching")
        .accessibilityHint("When enabled, tapped keys stay held for chord building")
    }

    /// Toolbar menu for selecting latency preset.
    var latencyMenu: some View {
        Menu {
            ForEach(LatencyPreset.allCases, id: \.self) { preset in
                Button {
                    viewModel.latencyPreset = preset
                    if viewModel.isListening {
                        viewModel.stopListening()
                        Task { await viewModel.startListening() }
                    }
                } label: {
                    HStack {
                        Text(preset.displayName)
                        if preset == viewModel.latencyPreset { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: "waveform.badge.magnifyingglass").font(.title3)
        }
        .accessibilityLabel("Latency preset")
        .accessibilityHint("Choose detection speed: fast, balanced, or precise")
    }
}

// MARK: - Formatting Helpers

extension PracticeTab {
    /// Color based on tuning accuracy.
    ///
    /// Green for within 5 cents, yellow for within 15 cents, orange otherwise.
    func centsColor(_ cents: Double) -> Color {
        let absCents = abs(cents)
        if absCents < 5 { return .green }
        if absCents < 15 { return .yellow }
        return .orange
    }

    /// Text label for cents offset.
    ///
    /// Returns "In Tune" when within 5 cents, otherwise the offset with direction.
    func centsText(_ cents: Double) -> String {
        let absCents = abs(cents)
        if absCents < 5 { return "In Tune" }
        let direction = cents > 0 ? "sharp" : "flat"
        return "\(Int(absCents))\u{00A2} \(direction)"
    }

    /// SF Symbol name for each expression type.
    func expressionIcon(_ type: ExpressionType) -> String {
        switch type {
        case .vibrato: "waveform.path"
        case .meend: "arrow.right"
        case .gamaka: "waveform"
        case .stable: "equal.circle"
        case .indeterminate: "questionmark.circle"
        }
    }

    /// Color for each expression type.
    func expressionColor(_ type: ExpressionType) -> Color {
        switch type {
        case .vibrato: .blue
        case .meend: .purple
        case .gamaka: .orange
        case .stable: .green
        case .indeterminate: .gray
        }
    }
}
