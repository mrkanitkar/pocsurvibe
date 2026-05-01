import SwiftUI

/// Picker for selecting the tonic Sa (C3-C5 range).
///
/// Displays a scrollable list of MIDI notes from C3 (48) to C5 (72),
/// each labeled with its Western note name and octave. Tapping a row
/// updates both the view model's live `tonicSaPitch` and the persisted
/// `SongProgress.preferredSaHz` for per-song recall.
struct TonicSaPickerContent: View {
    // MARK: - Properties

    @Bindable var viewModel: PlayAlongViewModel
    @Bindable var progress: SongProgress

    /// MIDI note range for Sa selection: C3 (48) through C5 (72).
    private static let midiRange: [Int] = Array(48...72)

    // MARK: - Body

    var body: some View {
        Form {
            Section("Tonic Sa") {
                ForEach(Self.midiRange, id: \.self) { midi in
                    saRow(midi: midi)
                }
            }
        }
        .navigationTitle("Tonic Sa")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Private Views

    /// A single selectable row for one MIDI pitch.
    @ViewBuilder
    private func saRow(midi: Int) -> some View {
        let isSelected = Int(viewModel.tonicSaPitch) == midi
        let name = WesternNoteHelper.displayName(from: midi)
        Button {
            viewModel.tonicSaPitch = UInt8(midi)
            progress.preferredSaHz = PlayAlongViewModel.saHz(
                forMIDIPitch: UInt8(midi)
            )
        } label: {
            HStack {
                Text(verbatim: name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TonicSaPickerContent(
            viewModel: PlayAlongViewModel(),
            progress: SongProgress()
        )
    }
}
