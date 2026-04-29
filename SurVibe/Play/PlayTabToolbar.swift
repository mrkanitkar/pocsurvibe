import SwiftUI

/// Top toolbar for the Play tab.
///
/// Hosts the instrument button (taps open the picker sheet via `onTapInstrument`),
/// notation segmented toggle, Sa-pitch menu, and MIDI status badge.
struct PlayTabToolbar: View {
    @Bindable
    var viewModel: PlayTabViewModel
    let connectedDeviceNames: [String]
    let onTapInstrument: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            instrumentButton
            notationToggle
            saPitchMenu
            Spacer(minLength: 8)
            midiStatusBadge
            recordingIndicator
            undoButton
            overflowMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular)
    }

    /// Red dot + monospaced clock counter; visible whenever the scratchpad
    /// has any captured content.
    @ViewBuilder
    private var recordingIndicator: some View {
        if viewModel.scratchpad.hasContent {
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                Text(viewModel.scratchpad.durationSec.formattedAsClock)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Recording \(viewModel.scratchpad.durationSec.formattedAsClock)"
            )
        }
    }

    /// Pops the most recently closed note from the scratchpad.
    private var undoButton: some View {
        Button {
            _ = viewModel.scratchpad.undoLastNote()
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .disabled(viewModel.scratchpad.notes.isEmpty)
        .accessibilityLabel("Undo last note")
        .accessibilityHint("Removes the most recently completed note from the recording")
    }

    /// Overflow stub — concrete entries (Save take, Takes…, New session, …)
    /// land in Tasks 13 / 14 / 16.
    private var overflowMenu: some View {
        Menu {
            // Intentionally empty in T6 — populated by later tasks.
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    private var instrumentButton: some View {
        Button(action: onTapInstrument) {
            Label(
                GMInstrumentCatalog.name(for: viewModel.currentInstrument),
                systemImage: "pianokeys"
            )
            .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Instrument")
        .accessibilityValue(GMInstrumentCatalog.name(for: viewModel.currentInstrument))
        .accessibilityHint("Opens the instrument picker")
    }

    private var notationToggle: some View {
        Picker("Notation", selection: $viewModel.notationMode) {
            Text("West").tag(PlayTabNotationMode.western)
            Text("Sgm").tag(PlayTabNotationMode.sargam)
            Text("Both").tag(PlayTabNotationMode.both)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)
        .accessibilityLabel("Notation system")
    }

    private var saPitchMenu: some View {
        Menu {
            ForEach(0..<12, id: \.self) { semitone in
                let midi = UInt8(60 + semitone)
                Button {
                    viewModel.setSaPitch(midi)
                } label: {
                    if midi == viewModel.saPitch {
                        Label(noteName(for: midi), systemImage: "checkmark")
                    } else {
                        Text(noteName(for: midi))
                    }
                }
            }
        } label: {
            Label("Sa: \(noteName(for: viewModel.saPitch))", systemImage: "tuningfork")
        }
        .accessibilityLabel("Sa pitch")
        .accessibilityValue(noteName(for: viewModel.saPitch))
    }

    @ViewBuilder
    private var midiStatusBadge: some View {
        if !connectedDeviceNames.isEmpty {
            Label {
                Text(midiBadgeText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: "pianokeys.inverse")
            }
            .foregroundStyle(Color.green)
            .accessibilityLabel("MIDI connected")
            .accessibilityValue(connectedDeviceNames.joined(separator: ", "))
        }
    }

    /// Display string for the MIDI badge: first device name, with " +N more"
    /// suffix when multiple devices are connected.
    private var midiBadgeText: String {
        if connectedDeviceNames.count <= 1 {
            return connectedDeviceNames.first ?? ""
        }
        return "\(connectedDeviceNames[0]) +\(connectedDeviceNames.count - 1) more"
    }

    private func noteName(for midi: UInt8) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return names[Int(midi) % 12]
    }
}

extension TimeInterval {
    /// Formats this interval as `m:ss` (e.g. `0:42`, `1:07`). Used by the
    /// recording-indicator counter on `PlayTabToolbar`.
    var formattedAsClock: String {
        let total = Int(self)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
