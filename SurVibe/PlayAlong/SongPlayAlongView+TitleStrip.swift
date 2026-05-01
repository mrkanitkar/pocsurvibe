import SVAudio
import SwiftUI

/// Compact title strip for the play-along minimal toolbar.
///
/// Displays the song title on the first line, with a three-element subtitle
/// row beneath: input badge (MIDI device name or "Mic"), Sa chip (tonic note
/// picker), and BPM badge showing the song's base tempo.
///
/// The Sa chip is a `Menu` that lets the user change the tonic pitch inline
/// without opening the full settings sheet.
struct SongPlayAlongTitleStrip: View {
    // MARK: - Properties

    /// View model for live state (tonic pitch, MIDI connection, hydration).
    @Bindable var viewModel: PlayAlongViewModel

    /// Title of the currently loaded song.
    let songTitle: String

    /// Artist or subtitle for the song.
    let songArtist: String

    /// Base tempo in BPM from the song metadata.
    let baseBPM: Int

    // MARK: - Body

    var body: some View {
        VStack(spacing: 2) {
            Text(verbatim: songTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 6) {
                inputBadge
                saChip
                bpmBadge
            }
            .font(.caption2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(songTitle), \(songArtist), Sa is \(saDisplayName), \(baseBPM) BPM"
        )
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Subviews

    /// Badge showing the active input source — MIDI device name or "Mic".
    private var inputBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(viewModel.isMIDIConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(verbatim: inputLabel)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .accessibilityLabel(
            viewModel.isMIDIConnected
                ? "MIDI connected: \(viewModel.midiDeviceName ?? "unknown")"
                : "Microphone input"
        )
    }

    /// The tonic Sa pitch picker, shown as a capsule chip.
    ///
    /// Displays a shimmer placeholder until `didInitialHydrate` is true,
    /// then shows a `Menu` with MIDI notes C3 (48) through C5 (72).
    @ViewBuilder
    private var saChip: some View {
        if viewModel.didInitialHydrate {
            Menu {
                ForEach(48...72, id: \.self) { midi in
                    let name = WesternNoteHelper.displayName(from: midi)
                    let isSelected = Int(viewModel.tonicSaPitch) == midi
                    Button {
                        viewModel.tonicSaPitch = UInt8(midi)
                    } label: {
                        if isSelected {
                            Label(name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: name)
                        }
                    }
                }
            } label: {
                Text(verbatim: "Sa = \(saDisplayName)")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Tonic Sa pitch")
            .accessibilityValue(saDisplayName)
            .accessibilityHint("Choose the tonic note for this song")
        } else {
            Text(verbatim: "Sa = ...")
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(.tertiarySystemBackground).opacity(0.5))
                .clipShape(Capsule())
                .accessibilityLabel("Loading tonic pitch")
        }
    }

    /// Badge showing the song's base BPM.
    private var bpmBadge: some View {
        Text(verbatim: "\(baseBPM) BPM")
            .foregroundStyle(.secondary)
            .accessibilityLabel("\(baseBPM) beats per minute")
    }

    // MARK: - Helpers

    /// Human-readable display name for the current tonic Sa pitch.
    private var saDisplayName: String {
        WesternNoteHelper.displayName(from: Int(viewModel.tonicSaPitch))
    }

    /// Label for the input badge — device name or "Mic".
    private var inputLabel: String {
        if viewModel.isMIDIConnected {
            return viewModel.midiDeviceName ?? "MIDI"
        }
        return viewModel.isMicEnabled ? "Mic" : "Touch"
    }
}

// MARK: - Preview

#Preview("Title Strip") {
    SongPlayAlongTitleStrip(
        viewModel: PlayAlongViewModel(),
        songTitle: "Raag Yaman",
        songArtist: "Aaroha",
        baseBPM: 120
    )
    .padding()
}
