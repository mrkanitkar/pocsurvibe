import SwiftUI

/// Small sheet for fine-grained tempo control via a slider and stepper.
///
/// Presented from the "Custom..." item in the toolbar tempo menu.
/// Range is 50%–150% (0.5–1.5 scale factor) with 5% steps.
/// Uses `.presentationDetents([.medium])` for a compact sheet.
struct TempoCustomSheet: View {
    // MARK: - Properties

    /// View model whose `tempoScale` is edited in place.
    @Bindable var viewModel: PlayAlongViewModel

    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text(verbatim: "\(percentLabel)%")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .accessibilityLabel("Tempo scale \(percentLabel) percent")

                Slider(
                    value: $viewModel.tempoScale,
                    in: 0.5...1.5,
                    step: 0.05
                )
                .accessibilityLabel("Tempo scale slider")
                .accessibilityValue("\(percentLabel) percent")
                .accessibilityHint("Adjust playback speed from 50 to 150 percent")

                Stepper(
                    value: $viewModel.tempoScale,
                    in: 0.5...1.5,
                    step: 0.05
                ) {
                    Text(verbatim: "\(percentLabel)%")
                        .monospacedDigit()
                }
                .accessibilityLabel("Fine tempo adjustment")
                .accessibilityValue("\(percentLabel) percent")
                .accessibilityHint("Increment or decrement tempo by 5 percent")

                Spacer()
            }
            .padding(24)
            .navigationTitle("Custom Tempo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityLabel("Done")
                    .accessibilityHint("Dismiss the custom tempo sheet")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    /// Current tempo scale formatted as an integer percentage.
    private var percentLabel: String {
        "\(Int((viewModel.tempoScale * 100).rounded()))"
    }
}

// MARK: - Preview

#Preview("Custom Tempo") {
    TempoCustomSheet(viewModel: PlayAlongViewModel())
}
