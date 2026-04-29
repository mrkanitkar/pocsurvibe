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
            midiAudioToggle
            Spacer(minLength: 8)
            midiStatusBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular)
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

    /// Toggles whether incoming MIDI also plays through the iPad sampler.
    /// Off by default — most users have a MIDI keyboard with built-in sound.
    private var midiAudioToggle: some View {
        Button {
            viewModel.setPlayAudioOnMIDI(!viewModel.playAudioOnMIDI)
        } label: {
            Image(
                systemName: viewModel.playAudioOnMIDI
                    ? "speaker.wave.2.fill" : "speaker.slash.fill"
            )
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("MIDI audio")
        .accessibilityValue(viewModel.playAudioOnMIDI ? "On" : "Off")
        .accessibilityHint("Toggles whether external MIDI input plays through the iPad sampler")
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
