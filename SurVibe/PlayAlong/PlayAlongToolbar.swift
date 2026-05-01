import SVAudio
import SwiftUI

/// Play-along "summoned toolbar" with title, timeline scrubber, and
/// practice controls.
///
/// All controls are driven by external state passed as `let` properties
/// with change callbacks. The toolbar adapts its layout horizontally and
/// provides full VoiceOver accessibility for every interactive element.
///
/// ## Layout
/// Three rows of controls:
/// 1. **Header:** Song title/subtitle (center) + Mode button (right).
///    Play/Pause is handled by the persistent pause dot, not by this toolbar.
/// 2. **Timeline:** Scrubber slider with elapsed/remaining time labels.
/// 3. **Controls:** BPM preset pills · Wait · Sound · Tanpura · MIDI/Mic source.
struct PlayAlongToolbar: View {
    // MARK: - Properties

    /// Bindable view model exposing Wave 4 D1 toolbar state (backing mode,
    /// tempo slider, hands picker, loop control, click level).
    ///
    /// Two-way bindings flow through this object to `PlayAlongViewModel`'s
    /// `backingMode`, `tempoScale`, `practiceMode`, `loopRegion`,
    /// `clickLevel`, and `showLoopBuilder` properties. Wave 5 E1 wires those
    /// onward to `ArrangementPlayer`.
    @Bindable var viewModel: PlayAlongViewModel

    /// Current playback state driving button icons and enabled states.
    let playbackState: PlaybackState

    /// Tempo multiplier (0.4x to 1.0x) applied to the song's base tempo.
    let tempoScale: Double

    /// Whether wait mode is active (pauses until player hits the correct note).
    let isWaitModeEnabled: Bool

    /// Whether reference audio playback is enabled.
    let isSoundEnabled: Bool

    /// Whether the tanpura reference drone is enabled.
    ///
    /// This is currently a UI-only toggle. Audio wiring is deferred to a
    /// follow-up task.
    var isTanpuraEnabled: Bool = false

    /// Whether a MIDI keyboard is currently connected via USB or Bluetooth.
    let isMIDIConnected: Bool

    /// Human-readable name of the connected MIDI device, or nil if none.
    let midiDeviceName: String?

    /// Base tempo in BPM from the loaded song, used to compute effective BPM display.
    ///
    /// Combined with `tempoScale` to show the effective BPM as "40% / 60% / 80% / 100%",
    /// giving the player discrete speed presets.
    var baseBPM: Int = 120

    /// Title of the currently loaded song.
    let songTitle: String

    /// Subtitle for the song (e.g., raga name or artist).
    let songSubtitle: String

    /// Playback progress as a normalized value from 0.0 (start) to 1.0 (end).
    let playbackProgress: Double

    /// Total duration of the song in seconds.
    let playbackDuration: TimeInterval

    // MARK: - Environment

    /// Whether the user has requested reduced motion in system accessibility settings.
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    // MARK: - Callbacks

    /// Called when the user taps Play or Pause.
    ///
    /// Retained for backward compatibility with existing call sites. The new
    /// summoned-toolbar layout hides play/pause from the header (the persistent
    /// pause dot handles it), so this closure is typically unused.
    var onPlayPause: () -> Void = {}

    /// Called when the user taps Stop.
    ///
    /// Retained for backward compatibility with existing call sites. The new
    /// layout does not surface a stop button in the toolbar.
    var onStop: () -> Void = {}

    /// Called when the user selects a tempo preset.
    var onTempoChange: (Double) -> Void

    /// Called when the user toggles wait mode.
    var onWaitModeToggle: () -> Void

    /// Called when the user toggles reference sound.
    var onSoundToggle: () -> Void

    /// Called when the user toggles the tanpura drone.
    var onTanpuraToggle: () -> Void = {}

    /// Called when the user taps the Mode button.
    ///
    /// The Mode button is intended to open Profile → Appearance so the player
    /// can switch themes. Wiring is deferred to a follow-up task; default is
    /// a no-op.
    var onModeTapped: () -> Void = {}

    /// Called when the user drags the timeline scrubber to a new position.
    ///
    /// - Parameter progress: Normalized position (0.0 to 1.0).
    var onSeek: (Double) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            headerRow
            timelineRow
            controlsRow
            arrangementControlsRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    }

    // MARK: - Row 4: Arrangement controls (Wave 4 D1)

    /// Backing-mode picker, tempo slider, hands picker, loop control, and
    /// (when backing == .click) click-level picker.
    ///
    /// All controls bind to `viewModel`. Wiring to `ArrangementPlayer` is
    /// deferred to Wave 5 (E1).
    private var arrangementControlsRow: some View {
        HStack(spacing: 12) {
            backingPicker
            tempoSlider
            handsPicker
            loopControl
            if viewModel.backingMode == .click {
                clickLevelPicker
            }
        }
    }

    /// Backing-accompaniment mode picker — On / Click / Off.
    private var backingPicker: some View {
        Picker("Backing", selection: $viewModel.backingMode) {
            Text("On").tag(PlayAlongViewModel.BackingMode.on)
            Text("Click").tag(PlayAlongViewModel.BackingMode.click)
            Text("Off").tag(PlayAlongViewModel.BackingMode.off)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .accessibilityLabel("Backing accompaniment mode")
        .accessibilityHint("Choose full backing, click track, or silent practice")
    }

    /// Continuous tempo scale slider in the range 50%..150%.
    private var tempoSlider: some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(Int((viewModel.tempoScale * 100).rounded()))%")
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Slider(
                value: $viewModel.tempoScale,
                in: 0.5...1.5,
                step: 0.05
            )
            .frame(width: 140)
            .accessibilityLabel("Tempo scale")
            .accessibilityValue(
                "\(Int((viewModel.tempoScale * 100).rounded())) percent"
            )
            .accessibilityHint("Adjust playback speed from 50 to 150 percent")
        }
    }

    /// Hand-isolation picker — Both / RH / LH. RH and LH disabled when the
    /// loaded arrangement has only one staff.
    private var handsPicker: some View {
        Picker("Hands", selection: $viewModel.practiceMode) {
            Text("Both").tag(PracticeMode.both)
            Text("RH")
                .tag(PracticeMode.rightHand)
            Text("LH")
                .tag(PracticeMode.leftHand)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        // The whole picker is disabled (rather than per-option) for a single-
        // staff arrangement: a segmented picker with one greyed segment reads
        // as broken, whereas a fully-disabled picker plus a clear hint
        // ("requires a multi-staff arrangement") communicates intent cleanly.
        .disabled(!viewModel.hasMultipleStaves)
        .accessibilityLabel("Hand isolation mode")
        .accessibilityHint(
            viewModel.hasMultipleStaves
                ? "Choose to practice both hands, right hand, or left hand"
                : "Hand isolation requires a multi-staff arrangement"
        )
    }

    /// Loop control — shows the active region with a clear button, or a
    /// trigger that opens the loop builder when no region is set.
    @ViewBuilder
    private var loopControl: some View {
        if let region = viewModel.loopRegion {
            Button {
                viewModel.loopRegion = nil
            } label: {
                Label(
                    "Loop m.\(region.startMeasure)\u{2013}\(region.endMeasure) \u{00D7}",
                    systemImage: "repeat"
                )
                .labelStyle(.titleOnly)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.18))
                .foregroundStyle(.primary)
                .clipShape(Capsule())
            }
            .accessibilityLabel(
                "Looping measures \(region.startMeasure) to \(region.endMeasure)"
            )
            .accessibilityHint("Tap to clear the loop region")
        } else {
            Button {
                viewModel.showLoopBuilder = true
            } label: {
                Label("Loop", systemImage: "repeat")
                    .labelStyle(.titleOnly)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Loop")
            .accessibilityHint("Open the loop builder to select a measure range")
        }
    }

    /// Click-track loudness picker — Soft / Normal / Loud. Visible only
    /// when the backing mode is `.click`.
    private var clickLevelPicker: some View {
        Picker("Click", selection: $viewModel.clickLevel) {
            Text("Soft").tag(PlayAlongViewModel.ClickLevel.soft)
            Text("Normal").tag(PlayAlongViewModel.ClickLevel.normal)
            Text("Loud").tag(PlayAlongViewModel.ClickLevel.loud)
        }
        .pickerStyle(.segmented)
        .frame(width: 160)
        .accessibilityLabel("Click track loudness")
        .accessibilityHint("Choose soft, normal, or loud click volume")
    }

    // MARK: - Row 1: Header

    /// Song title/subtitle (centered) and Mode button on the trailing side.
    ///
    /// A 44pt-wide leading gutter visually balances the Mode button so the
    /// song info stays optically centered. Play/Pause has moved to the
    /// persistent pause dot and is no longer shown here.
    private var headerRow: some View {
        HStack(spacing: 12) {
            Spacer()
                .frame(width: 44)
                .accessibilityHidden(true)
            songInfo
            modeButton
        }
    }

    /// Button that opens the theme/appearance entry point (Profile → Appearance).
    private var modeButton: some View {
        Button(action: onModeTapped) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.body)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Theme mode")
        .accessibilityHint("Open Profile to change theme")
    }

    /// Song title and subtitle, centered in the available space.
    private var songInfo: some View {
        VStack(spacing: 2) {
            Text(verbatim: songTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            if !songSubtitle.isEmpty {
                Text(verbatim: songSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(songTitle), \(songSubtitle)")
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Row 2: Timeline

    /// Timeline scrubber showing current position and total duration.
    private var timelineRow: some View {
        HStack(spacing: 8) {
            Text(verbatim: PlayAlongToolbar.formatTime(playbackProgress * playbackDuration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { playbackProgress },
                    set: { onSeek($0) }
                ),
                in: 0.0...1.0
            )
            .accessibilityLabel("Playback position")
            .accessibilityValue(
                """
                \(PlayAlongToolbar.formatTime(playbackProgress * playbackDuration)) \
                of \(PlayAlongToolbar.formatTime(playbackDuration))
                """
            )
            .accessibilityHint("Drag to seek to a different position in the song")

            Text(verbatim: PlayAlongToolbar.formatTime(playbackDuration))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Row 3: Controls

    /// BPM preset pills, divider, and wait/sound/tanpura/source controls.
    private var controlsRow: some View {
        HStack(spacing: 10) {
            tempoPills
            divider
            waitModeButton
            soundToggleButton
            tanpuraToggleButton
            midiStatusPill
        }
    }

    /// Four discrete tempo preset buttons (40%, 60%, 80%, 100%).
    private var tempoPills: some View {
        HStack(spacing: 6) {
            ForEach(Self.tempoPresets, id: \.self) { preset in
                Button {
                    onTempoChange(preset)
                } label: {
                    Text(verbatim: "\(Int(preset * 100))%")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            abs(tempoScale - preset) < 0.01
                                ? Color.accentColor
                                : Color(.tertiarySystemBackground)
                        )
                        .foregroundStyle(
                            abs(tempoScale - preset) < 0.01 ? .white : .primary
                        )
                        .clipShape(Capsule())
                }
                .accessibilityLabel("\(Int(preset * 100)) percent tempo")
                .accessibilityHint("Set playback speed to \(Int(preset * 100)) percent")
                .accessibilityAddTraits(
                    abs(tempoScale - preset) < 0.01 ? .isSelected : []
                )
            }
        }
    }

    /// Visual separator between tempo pills and toggle controls.
    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 1, height: 20)
            .accessibilityHidden(true)
    }

    /// A non-interactive status pill showing MIDI connection state.
    ///
    /// Green dot = MIDI keyboard connected. Gray dot = mic-only mode.
    private var midiStatusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isMIDIConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(isMIDIConnected ? (midiDeviceName ?? "MIDI") : "Mic")
                .font(.caption2)
                .foregroundStyle(isMIDIConnected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isMIDIConnected
                ? Color.green.opacity(0.12)
                : Color(.tertiarySystemBackground)
        )
        .clipShape(Capsule())
        .accessibilityLabel(
            isMIDIConnected
                ? "MIDI keyboard connected: \(midiDeviceName ?? "unknown device")"
                : "Microphone input active"
        )
        .accessibilityAddTraits(.isStaticText)
    }

    /// Toggle for wait mode (pauses until the player hits the correct note).
    private var waitModeButton: some View {
        Button(action: onWaitModeToggle) {
            Image(systemName: "hourglass")
                .accessibilityHidden(true)
                .font(.body)
                .frame(width: 36, height: 36)
                .foregroundStyle(isWaitModeEnabled ? .white : .primary)
                .background(isWaitModeEnabled ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Wait mode")
        .accessibilityValue(isWaitModeEnabled ? "On" : "Off")
        .accessibilityHint("When enabled, playback pauses until you play the correct note")
    }

    /// Toggle for reference sound playback.
    private var soundToggleButton: some View {
        Button(action: onSoundToggle) {
            Image(systemName: isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.body)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(isSoundEnabled ? "Sound on" : "Sound off")
        .accessibilityHint("Toggle reference audio playback")
    }

    /// Toggle for the tanpura reference drone.
    ///
    /// Currently a UI-only toggle — audio wiring is deferred.
    private var tanpuraToggleButton: some View {
        Button(action: onTanpuraToggle) {
            Image(systemName: "waveform.path.ecg")
                .accessibilityHidden(true)
                .font(.body)
                .frame(width: 36, height: 36)
                .foregroundStyle(isTanpuraEnabled ? .white : .primary)
                .background(isTanpuraEnabled ? Color.accentColor : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel("Tanpura drone")
        .accessibilityValue(isTanpuraEnabled ? "On" : "Off")
        .accessibilityHint("Toggle tanpura reference drone")
    }

    // MARK: - Computed Properties

    /// SF Symbol name for the play/pause button based on current playback state.
    static func playPauseIcon(for state: PlaybackState) -> String {
        switch state {
        case .playing:
            "pause.fill"
        default:
            "play.fill"
        }
    }

    // MARK: - Constants

    /// Available tempo scale presets shown as pill buttons.
    private static let tempoPresets: [Double] = [0.4, 0.6, 0.8, 1.0]

    // MARK: - Static Helpers

    /// Format a time interval as "m:ss".
    ///
    /// - Parameter time: Time in seconds to format.
    /// - Returns: Formatted string in "m:ss" format (e.g., "3:42").
    static func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(time, 0)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Format tempo as "quarter-note = 72 BPM (60%)" given a scale and base BPM.
    ///
    /// - Parameters:
    ///   - scale: The tempo multiplier (0.4-1.0).
    ///   - baseBPM: The song's original BPM.
    /// - Returns: Formatted string like "quarter-note = 72 BPM (60%)".
    static func formatTempoBPM(scale: Double, baseBPM: Int) -> String {
        let effectiveBPM = Int((Double(baseBPM) * scale).rounded())
        let percent = Int((scale * 100).rounded())
        return "\u{2669} = \(effectiveBPM) BPM (\(percent)%)"
    }

    /// Format tempo scale as a short percentage string (e.g. "75%").
    ///
    /// - Parameter scale: The tempo multiplier value.
    /// - Returns: Formatted string like "75%" or "100%".
    static func formatTempoLabel(_ scale: Double) -> String {
        "\(Int((scale * 100).rounded()))%"
    }

    /// Format a tempo scale value as a human-readable string.
    ///
    /// Kept for backward compatibility with existing tests.
    ///
    /// - Parameter scale: The tempo multiplier value.
    /// - Returns: Formatted percentage string like "75%".
    static func formatTempoScale(_ scale: Double) -> String {
        formatTempoLabel(scale)
    }

}

// MARK: - Preview

#Preview("Toolbar — Idle") {
    PlayAlongToolbar(
        viewModel: PlayAlongViewModel(),
        playbackState: .idle,
        tempoScale: 1.0,
        isWaitModeEnabled: false,
        isSoundEnabled: true,
        isTanpuraEnabled: false,
        isMIDIConnected: false,
        midiDeviceName: nil,
        baseBPM: 120,
        songTitle: "Aarohan Practice",
        songSubtitle: "Raga Yaman",
        playbackProgress: 0.0,
        playbackDuration: 180,
        onPlayPause: {},
        onStop: {},
        onTempoChange: { _ in },
        onWaitModeToggle: {},
        onSoundToggle: {},
        onTanpuraToggle: {},
        onModeTapped: {},
        onSeek: { _ in }
    )
}

#Preview("Toolbar — Playing") {
    PlayAlongToolbar(
        viewModel: PlayAlongViewModel(),
        playbackState: .playing,
        tempoScale: 0.6,
        isWaitModeEnabled: true,
        isSoundEnabled: false,
        isTanpuraEnabled: true,
        isMIDIConnected: true,
        midiDeviceName: "Yamaha PSR-400",
        baseBPM: 100,
        songTitle: "Teentaal Drut",
        songSubtitle: "Raga Bhairav",
        playbackProgress: 0.35,
        playbackDuration: 225,
        onPlayPause: {},
        onStop: {},
        onTempoChange: { _ in },
        onWaitModeToggle: {},
        onSoundToggle: {},
        onTanpuraToggle: {},
        onModeTapped: {},
        onSeek: { _ in }
    )
}
