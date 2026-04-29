import SwiftUI

/// Top toolbar for the Play tab.
///
/// Hosts the instrument button (taps open the picker sheet via `onTapInstrument`),
/// notation segmented toggle, Sa-pitch menu, and MIDI status badge.
struct PlayTabToolbar: View {
    @Bindable
    var viewModel: PlayTabViewModel
    let connectedDeviceNames: [String]
    /// Optional guard for the ⋯ → "New session" entry. When `nil` (e.g.
    /// previews) New session bypasses the dialog and clears immediately.
    var scratchpadGuard: UnsavedScratchpadGuard?
    let onTapInstrument: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            instrumentButton
            notationToggle
            saPitchMenu
            Spacer(minLength: 4)
            midiStatusBadge
            undoButton
            overflowMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    private var notationToggle: some View {
        Picker("Notation", selection: $viewModel.notationMode) {
            Text("West").tag(PlayTabNotationMode.western)
            Text("Sgm").tag(PlayTabNotationMode.sargam)
            Text("Both").tag(PlayTabNotationMode.both)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 180)
        .accessibilityLabel("Notation system")
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

    /// Overflow menu. Currently exposes "New session" — additional entries
    /// (Save take, Takes…, Export, …) populated by later tasks.
    private var overflowMenu: some View {
        Menu {
            Button {
                triggerNewSession()
            } label: {
                Label("New session", systemImage: "doc.badge.plus")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    /// Route "New session" through the guard when the scratchpad has
    /// content; otherwise clear immediately.
    private func triggerNewSession() {
        if viewModel.scratchpad.hasContent, let guardObj = scratchpadGuard {
            guardObj.raise(.newSession) { outcome in
                switch outcome {
                case .save:
                    viewModel.saveTakeSheetPresented = true
                case .discard:
                    viewModel.clearScratchpad(programOverride: nil, saOverride: nil)
                case .cancel:
                    break
                }
            }
        } else {
            viewModel.clearScratchpad(programOverride: nil, saOverride: nil)
        }
    }

    private var instrumentButton: some View {
        // Icon + truncated name so the toolbar fits beside iPadOS's
        // centred floating tab-chip without overflowing into it. Tap to
        // open the full instrument picker (where the user sees the long
        // GM name + browses categories).
        Button(action: onTapInstrument) {
            HStack(spacing: 4) {
                Image(systemName: "pianokeys")
                Text(GMInstrumentCatalog.name(for: viewModel.currentInstrument))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 110, alignment: .leading)
            }
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Instrument")
        .accessibilityValue(GMInstrumentCatalog.name(for: viewModel.currentInstrument))
        .accessibilityHint("Opens the instrument picker")
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
