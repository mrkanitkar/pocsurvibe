import SwiftData
import SwiftUI

/// Settings panel for the play-along experience.
///
/// Presented as a `.sheet` with `.presentationDetents([.medium, .large])`.
/// At `.medium` detent, background interaction is enabled so the user can
/// keep playing while configuring. Contains six sections: Song, Tuning,
/// Parts, Practice aids, Input, and Appearance.
struct PlayAlongSettingsSheet: View {
    // MARK: - Properties

    @Bindable var viewModel: PlayAlongViewModel
    @Bindable var tanpura: TanpuraController
    let song: Song
    @Bindable var progress: SongProgress
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                songSection
                tuningSection
                partsSection
                practiceAidsSection
                inputSection
                appearanceSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .accessibilityLabel("Close settings")
                    .accessibilityHint("Dismisses the settings panel")
                }
            }
        }
    }

    // MARK: - Song Section

    /// Read-only metadata chips for the loaded song.
    @ViewBuilder
    private var songSection: some View {
        Section {
            ChipRow(
                title: song.title,
                badges: songBadges
            )
        }
    }

    /// Assemble badge strings from the song's metadata.
    private var songBadges: [String] {
        var badges: [String] = []
        if !song.artist.isEmpty {
            badges.append(song.artist)
        }
        badges.append(difficultyLabel(song.difficulty))
        if !song.language.isEmpty {
            badges.append(song.language)
        }
        badges.append(formattedDuration(song.durationSeconds))
        return badges
    }

    /// Human-readable difficulty label from the integer level.
    private func difficultyLabel(_ level: Int) -> String {
        switch level {
        case 1: "Beginner"
        case 2: "Easy"
        case 3: "Medium"
        case 4: "Hard"
        case 5: "Expert"
        default: "Level \(level)"
        }
    }

    /// Format seconds into a "Xm Ys" or "Xm" duration string.
    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if secs == 0 {
            return "\(minutes)m"
        }
        return "\(minutes)m \(secs)s"
    }

    // MARK: - Tuning Section

    /// Tonic Sa pitch picker.
    @ViewBuilder
    private var tuningSection: some View {
        Section("Tuning") {
            DisclosureRow(
                title: "Tonic Sa",
                value: WesternNoteHelper.displayName(from: Int(viewModel.tonicSaPitch))
            ) {
                TonicSaPickerContent(
                    viewModel: viewModel,
                    progress: progress
                )
            }
        }
    }

    // MARK: - Parts Section

    /// Learner track, hand isolation, and preview buttons.
    @ViewBuilder
    private var partsSection: some View {
        Section("Parts") {
            if let indices = song.learnerTrackIndices, indices.count > 1 {
                Picker("Learner track", selection: $progress.preferredLearnerTrackIndex) {
                    ForEach(indices, id: \.self) { index in
                        Text(trackLabel(for: index))
                            .tag(index)
                    }
                }
                .accessibilityLabel("Learner track")
                .accessibilityHint("Select which track to practice")
            }

            if viewModel.hasMultipleStaves {
                Picker("Hands", selection: $progress.preferredHands) {
                    Text("Both").tag("both")
                    Text("Right hand").tag("rh")
                    Text("Left hand").tag("lh")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Hand selection")
                .accessibilityHint("Choose which hands to practice")
            }

            ActionRow(
                title: "Preview learner part",
                systemImage: "play.fill",
                isEnabled: !viewModel.isPlaying
            ) {
                Task { await viewModel.previewLearnerPart() }
            }

            ActionRow(
                title: "Preview backing",
                systemImage: "music.note.list",
                isEnabled: !viewModel.isPlaying
            ) {
                Task { await viewModel.previewBackingPart() }
            }
        }
    }

    /// Label for a learner track index, using accompaniment summary if available.
    private func trackLabel(for index: Int) -> String {
        if let summary = song.accompanimentInstrumentSummary, !summary.isEmpty {
            return summary
        }
        return "Track \(index)"
    }

    // MARK: - Practice Aids Section

    /// Wait mode, click track, tanpura, loop, and sound toggles.
    @ViewBuilder
    private var practiceAidsSection: some View {
        Section("Practice Aids") {
            ToggleRow(
                title: "Wait mode",
                isOn: $progress.waitModeEnabled,
                hint: "Pauses playback until you play the correct note"
            )

            ToggleRow(
                title: "Click track",
                isOn: $progress.clickTrackEnabled,
                hint: "Plays a metronome click on each beat"
            )

            if progress.clickTrackEnabled {
                Picker("Click level", selection: $progress.clickTrackLevel) {
                    Text("Soft").tag("soft")
                    Text("Normal").tag("normal")
                    Text("Loud").tag("loud")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Click track level")
                .accessibilityHint("Adjust the click track volume")
            }

            DisclosureRow(
                title: "Tanpura",
                value: tanpura.isTanpuraEnabled ? "On" : "Off"
            ) {
                TanpuraSettingsContent(
                    controller: tanpura,
                    canResetToSongDefault: !progress.tanpuraRaga.isEmpty,
                    onResetToSongDefault: {
                        // Reset tanpura to the song's default raga tuning
                    }
                )
            }

            DisclosureRow(
                title: "Loop",
                value: loopValueLabel
            ) {
                LoopBuilderContent(
                    totalMeasures: viewModel.totalMeasures,
                    initialStart: progress.loopRegionStart ?? 1,
                    initialEnd: progress.loopRegionEnd
                ) { region in
                    if let region {
                        progress.loopRegionStart = region.startMeasure
                        progress.loopRegionEnd = region.endMeasure
                        viewModel.loopRegion = region
                    } else {
                        progress.loopRegionStart = nil
                        progress.loopRegionEnd = nil
                        viewModel.loopRegion = nil
                    }
                }
            }

            ToggleRow(
                title: "Sound",
                isOn: $viewModel.isSoundEnabled,
                hint: "Enables playback audio for the backing track"
            )
        }
    }

    /// Formatted loop region label, or "Off" when no loop is set.
    private var loopValueLabel: String {
        if let start = progress.loopRegionStart,
            let end = progress.loopRegionEnd
        {
            return "m\(start)–m\(end)"
        }
        return "Off"
    }

    // MARK: - Input Section

    /// MIDI device status and microphone toggle.
    @ViewBuilder
    private var inputSection: some View {
        Section("Input") {
            HStack {
                Image(systemName: viewModel.isMIDIConnected ? "pianokeys" : "pianokeys")
                    .foregroundStyle(viewModel.isMIDIConnected ? .green : .secondary)
                    .accessibilityHidden(true)
                Text(viewModel.midiDeviceName ?? "No MIDI device")
                    .foregroundStyle(viewModel.isMIDIConnected ? .primary : .secondary)
                Spacer()
                if viewModel.isMIDIConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                viewModel.isMIDIConnected
                    ? "MIDI device connected: \(viewModel.midiDeviceName ?? "Unknown")"
                    : "No MIDI device connected"
            )

            ToggleRow(
                title: "Microphone",
                isOn: $viewModel.isMicEnabled,
                hint: "Enables pitch detection from the microphone"
            )
        }
    }

    // MARK: - Appearance Section

    /// Theme picker via disclosure to the carousel.
    @ViewBuilder
    private var appearanceSection: some View {
        Section("Appearance") {
            DisclosureRow(
                title: "Theme",
                value: nil
            ) {
                ThemeCarouselContent()
                    .navigationTitle("Theme")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PlayAlongSettingsSheet(
        viewModel: PlayAlongViewModel(),
        tanpura: TanpuraController(),
        song: Song(),
        progress: SongProgress()
    )
}
