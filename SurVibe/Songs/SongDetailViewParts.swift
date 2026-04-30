import SwiftUI

/// "Parts" section for ``SongDetailView``: lets the learner choose which
/// track they will play, see the backing instruments, pick a tonic Sa
/// pitch, and preview either the learner part or the backing.
///
/// This is a Wave 4 D2 stub view. Preview button callbacks are wired
/// through to the parent — Wave 5 (E1) will hook them up to
/// ``ArrangementPlayer``. The Sa picker stores its value via the
/// supplied `@Binding`; persistence (e.g., onto `SongProgress`) is the
/// caller's responsibility.
@MainActor
struct SongDetailViewParts: View {
    // MARK: - Properties

    /// The song this picker section is for. Used for VoiceOver context only.
    let song: Song

    /// Display labels for each selectable track. Index 0 is conventionally
    /// the learner part. See ``SongDetailViewParts/trackLabels(for:)``.
    let trackLabels: [String]

    /// Display labels for the accompaniment instruments. Joined with " · "
    /// in the "Backing:" row. Empty when the song has no accompaniment.
    let accompanimentInstruments: [String]

    /// Selected learner track index, two-way bound to the parent.
    @Binding var learnerTrackIndex: Int

    /// Selected tonic Sa as a MIDI pitch number (range 48...72).
    @Binding var tonicSaPitch: UInt8

    /// Invoked when the user taps "Preview my part".
    let onPreviewLearner: () -> Void

    /// Invoked when the user taps "Preview backing".
    let onPreviewBacking: () -> Void

    // MARK: - Initialization

    /// Creates a Parts section view.
    ///
    /// - Parameters:
    ///   - song: Song the section belongs to (for accessibility context).
    ///   - trackLabels: Selectable track display labels.
    ///   - accompanimentInstruments: Backing instrument display labels.
    ///   - learnerTrackIndex: Binding to the selected learner track index.
    ///   - tonicSaPitch: Binding to the selected tonic Sa MIDI pitch.
    ///   - onPreviewLearner: Callback for the "Preview my part" button.
    ///   - onPreviewBacking: Callback for the "Preview backing" button.
    init(
        song: Song,
        trackLabels: [String],
        accompanimentInstruments: [String],
        learnerTrackIndex: Binding<Int>,
        tonicSaPitch: Binding<UInt8>,
        onPreviewLearner: @escaping () -> Void,
        onPreviewBacking: @escaping () -> Void
    ) {
        self.song = song
        self.trackLabels = trackLabels
        self.accompanimentInstruments = accompanimentInstruments
        self._learnerTrackIndex = learnerTrackIndex
        self._tonicSaPitch = tonicSaPitch
        self.onPreviewLearner = onPreviewLearner
        self.onPreviewBacking = onPreviewBacking
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parts")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Text("I'll play:")
                Picker("I'll play", selection: $learnerTrackIndex) {
                    ForEach(Array(trackLabels.enumerated()), id: \.offset) { idx, label in
                        Text(label).tag(idx)
                    }
                }
                .accessibilityLabel("Learner part picker")
                .accessibilityHint("Choose which track you will play")
            }

            HStack {
                Text("Backing:")
                Text(
                    accompanimentInstruments.isEmpty
                        ? "—"
                        : accompanimentInstruments.joined(separator: " · ")
                )
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    accompanimentInstruments.isEmpty
                        ? "No backing instruments"
                        : "Backing instruments: " + accompanimentInstruments.joined(separator: ", ")
                )
            }

            HStack {
                Text("Tonic Sa:")
                Picker("Tonic Sa", selection: $tonicSaPitch) {
                    ForEach(48...72, id: \.self) { midiNote in
                        Text(Self.noteName(UInt8(midiNote))).tag(UInt8(midiNote))
                    }
                }
                .accessibilityLabel("Tonic Sa pitch picker")
                .accessibilityHint("Choose the tonic note Sa as a MIDI pitch")
            }

            HStack {
                // TODO(E1): wire to ArrangementPlayer.previewLearner() in Wave 5.
                Button(action: onPreviewLearner) {
                    Label("Preview my part", systemImage: "play.fill")
                }
                .accessibilityLabel("Preview my part")
                .accessibilityHint("Play a short preview of the learner part")

                // TODO(E1): wire to ArrangementPlayer.previewBacking() in Wave 5.
                Button(action: onPreviewBacking) {
                    Label("Preview backing", systemImage: "play.fill")
                }
                .accessibilityLabel("Preview backing")
                .accessibilityHint("Play a short preview of the backing accompaniment")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular)
    }

    // MARK: - Helpers

    /// Computes display labels for the picker from a Song's projected
    /// accompaniment summary.
    ///
    /// Falls back to a single "Piano" entry when the song has no multi-part
    /// metadata. When `accompanimentInstrumentSummary` is present (a
    /// " · "-joined string built at import time), prepends a "Learner"
    /// entry so the user can pick their own part.
    ///
    /// Note: persisting a learner instrument label on Song is deferred to a
    /// later wave so we can show e.g. "Piano (you)" instead of "Learner".
    ///
    /// - Parameter song: Song to derive labels from.
    /// - Returns: Display labels for each selectable track, in track order.
    static func trackLabels(for song: Song) -> [String] {
        guard let summary = song.accompanimentInstrumentSummary, !summary.isEmpty else {
            return ["Piano"]
        }
        let accompaniment = summary
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return ["Learner"] + accompaniment
    }

    /// Formats a MIDI pitch as a Western note name with octave.
    ///
    /// Uses the SPN convention where MIDI 60 = `C4`. Sharps are used for
    /// the five black keys; flats are not produced.
    ///
    /// - Parameter midi: MIDI pitch number (0...127).
    /// - Returns: Note name like `"C4"`, `"F#3"`, `"G4"`.
    static func noteName(_ midi: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let pitchClass = Int(midi) % 12
        let octave = Int(midi) / 12 - 1
        return "\(names[pitchClass])\(octave)"
    }
}

// MARK: - Preview

#Preview("Single-track") {
    @Previewable @State var learner = 0
    @Previewable @State var sa: UInt8 = 60
    let song = Song(
        slugId: "preview-single",
        title: "Preview Single",
        artist: "Demo",
        language: "en",
        difficulty: 1,
        category: "classical",
        ragaName: "",
        tempo: 80,
        durationSeconds: 60
    )
    return SongDetailViewParts(
        song: song,
        trackLabels: SongDetailViewParts.trackLabels(for: song),
        accompanimentInstruments: [],
        learnerTrackIndex: $learner,
        tonicSaPitch: $sa,
        onPreviewLearner: {},
        onPreviewBacking: {}
    )
    .padding()
}

#Preview("Multi-track") {
    @Previewable @State var learner = 0
    @Previewable @State var sa: UInt8 = 62
    let song = Song(
        slugId: "preview-multi",
        title: "Preview Multi",
        artist: "Demo",
        language: "en",
        difficulty: 2,
        category: "classical",
        ragaName: "Yaman",
        tempo: 90,
        durationSeconds: 180
    )
    song.accompanimentInstrumentSummary = "Harmonium · Tabla · Strings"
    return SongDetailViewParts(
        song: song,
        trackLabels: SongDetailViewParts.trackLabels(for: song),
        accompanimentInstruments: ["Harmonium", "Tabla", "Strings"],
        learnerTrackIndex: $learner,
        tonicSaPitch: $sa,
        onPreviewLearner: {},
        onPreviewBacking: {}
    )
    .padding()
}
