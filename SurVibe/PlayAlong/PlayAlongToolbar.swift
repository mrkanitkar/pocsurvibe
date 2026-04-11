import SVAudio
import SwiftUI

/// Top toolbar providing play-along transport controls, tempo adjustment,
/// and display mode toggles.
///
/// All controls are driven by external state passed as `let` properties
/// with change callbacks. The toolbar adapts its layout horizontally and
/// provides full VoiceOver accessibility for every interactive element.
///
/// ## Layout
/// Two rows of controls:
/// 1. Transport row: Play/Pause, Stop, Tempo slider
/// 2. Options row: Wait Mode, Sound toggle, View Mode, Notation Mode
struct PlayAlongToolbar: View {
    // MARK: - Properties

    /// Current playback state driving button icons and enabled states.
    let playbackState: PlaybackState

    /// Tempo multiplier (0.25x to 1.5x) applied to the song's base tempo.
    let tempoScale: Double

    /// Whether wait mode is active (pauses until player hits the correct note).
    let isWaitModeEnabled: Bool

    /// Whether reference audio playback is enabled.
    let isSoundEnabled: Bool

    /// Current visual mode (falling notes or scrolling sheet).
    let viewMode: PlayAlongViewMode

    /// Current notation display mode (sargam, western, dual, etc.).
    let notationMode: NotationDisplayMode

    /// Whether a MIDI keyboard is currently connected via USB or Bluetooth.
    let isMIDIConnected: Bool

    /// Human-readable name of the connected MIDI device, or nil if none.
    let midiDeviceName: String?

    /// Current latency preset for mic pitch detection.
    let latencyPreset: LatencyPreset

    /// Base tempo in BPM from the loaded song, used to compute effective BPM display.
    ///
    /// Combined with `tempoScale` to show the effective BPM as "♩ = 72 BPM (60%)",
    /// giving the player a concrete sense of the actual playback speed.
    var baseBPM: Int = 120

    // MARK: - Callbacks

    /// Called when the user taps Play or Pause.
    var onPlayPause: () -> Void

    /// Called when the user taps Stop.
    var onStop: () -> Void

    /// Called when the user adjusts the tempo slider.
    var onTempoChange: (Double) -> Void

    /// Called when the user toggles wait mode.
    var onWaitModeToggle: () -> Void

    /// Called when the user toggles reference sound.
    var onSoundToggle: () -> Void

    /// Called when the user changes the view mode.
    var onViewModeChange: (PlayAlongViewMode) -> Void

    /// Called when the user changes the notation mode.
    var onNotationModeChange: (NotationDisplayMode) -> Void

    /// Called when the user selects a different latency preset.
    var onLatencyPresetChange: (LatencyPreset) -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: 8) {
            transportRow
            optionsRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Transport Row

    /// Play/Pause, Stop, and tempo slider in a horizontal row.
    private var transportRow: some View {
        HStack(spacing: 12) {
            playPauseButton
            stopButton
            tempoSlider
        }
    }

    /// Play/Pause toggle button with state-driven icon.
    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            Image(systemName: playPauseIconName)
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .disabled(isPlayPauseDisabled)
        .accessibilityLabel(playPauseAccessibilityLabel)
        .accessibilityHint(playPauseAccessibilityHint)
    }

    /// Stop button that resets playback to the beginning.
    private var stopButton: some View {
        Button(action: onStop) {
            Image(systemName: "stop.fill")
                .font(.title2)
                .frame(width: 44, height: 44)
        }
        .disabled(isStopDisabled)
        .accessibilityLabel("Stop")
        .accessibilityHint("Stop playback and return to the beginning")
    }

    /// Tempo controls: preset buttons and a 40%–100% slider.
    private var tempoSlider: some View {
        VStack(spacing: 4) {
            // Preset buttons
            HStack(spacing: 6) {
                ForEach([0.4, 0.6, 0.8, 1.0], id: \.self) { preset in
                    Button {
                        onTempoChange(preset)
                    } label: {
                        Text("\(Int(preset * 100))%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
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
                }
            }
            // Slider
            HStack(spacing: 4) {
                Text(PlayAlongToolbar.formatTempoBPM(scale: tempoScale, baseBPM: baseBPM))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 120, alignment: .trailing)
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(
                        get: { tempoScale },
                        set: { onTempoChange($0) }
                    ),
                    in: 0.4...1.0,
                    step: 0.1
                )
                .accessibilityLabel("Tempo speed")
                .accessibilityValue(PlayAlongToolbar.formatTempoBPM(scale: tempoScale, baseBPM: baseBPM))
                .accessibilityHint("Adjust playback speed from 40 percent to 100 percent")
            }
        }
    }

    // MARK: - Options Row

    /// Wait mode, sound toggle, MIDI status pill, latency menu, view mode picker, and notation mode picker.
    private var optionsRow: some View {
        HStack(spacing: 12) {
            waitModeButton
            soundToggleButton
            midiStatusPill
            Spacer()
            latencyPresetMenu
            viewModePicker
            notationModePicker
        }
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

    /// Menu for selecting the mic detection latency preset.
    ///
    /// Mirrors the latency menu on the Practice tab — 4 presets from ~23ms
    /// (Ultra Fast, lowest accuracy) to ~186ms (Precise, highest accuracy).
    private var latencyPresetMenu: some View {
        Menu {
            ForEach(LatencyPreset.allCases, id: \.self) { preset in
                Button {
                    onLatencyPresetChange(preset)
                } label: {
                    HStack {
                        Text(preset.displayName)
                        if preset == latencyPreset {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityLabel(preset.displayName)
            }
        } label: {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.body)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel("Detection latency")
        .accessibilityValue(latencyPreset.displayName)
        .accessibilityHint("Select mic detection speed vs accuracy tradeoff")
    }

    /// Picker to switch between falling notes and scrolling sheet modes.
    private var viewModePicker: some View {
        Picker("View", selection: Binding(
            get: { viewMode },
            set: { onViewModeChange($0) }
        )) {
            ForEach(PlayAlongViewMode.allCases, id: \.self) { mode in
                Label(mode.label, systemImage: mode.iconName)
                    .tag(mode)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("View mode")
        .accessibilityHint("Switch between falling notes and sheet view")
    }

    /// Picker to switch notation display modes.
    private var notationModePicker: some View {
        Picker("Notation", selection: Binding(
            get: { notationMode },
            set: { onNotationModeChange($0) }
        )) {
            ForEach(NotationDisplayMode.allCases, id: \.self) { mode in
                Label(mode.label, systemImage: mode.iconName)
                    .tag(mode)
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("Notation mode")
        .accessibilityHint("Choose notation display style")
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

    /// Returns the SF Symbol name for the current playback state.
    private var playPauseIconName: String {
        Self.playPauseIcon(for: playbackState)
    }

    /// VoiceOver label for the play/pause button.
    private var playPauseAccessibilityLabel: String {
        switch playbackState {
        case .playing:
            "Pause"
        default:
            "Play"
        }
    }

    /// VoiceOver hint for the play/pause button.
    private var playPauseAccessibilityHint: String {
        switch playbackState {
        case .playing:
            "Pause song playback"
        case .paused:
            "Resume song playback"
        default:
            "Start playing the song"
        }
    }

    /// Whether the play/pause button should be disabled.
    private var isPlayPauseDisabled: Bool {
        switch playbackState {
        case .loading, .error:
            true
        default:
            false
        }
    }

    /// Whether the stop button should be disabled.
    private var isStopDisabled: Bool {
        switch playbackState {
        case .idle, .loading, .stopped, .error:
            true
        case .playing, .paused:
            false
        }
    }

    // MARK: - Static Helpers

    /// Format tempo as "♩ = 72 BPM (60%)" given a scale and base BPM.
    ///
    /// - Parameters:
    ///   - scale: The tempo multiplier (0.4–1.0).
    ///   - baseBPM: The song's original BPM.
    /// - Returns: Formatted string like "♩ = 72 BPM (60%)".
    static func formatTempoBPM(scale: Double, baseBPM: Int) -> String {
        let effectiveBPM = Int((Double(baseBPM) * scale).rounded())
        let percent = Int((scale * 100).rounded())
        return "♩ = \(effectiveBPM) BPM (\(percent)%)"
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

    /// Clamp a tempo scale value to the valid range (40%–100%).
    ///
    /// - Parameter scale: The raw tempo multiplier.
    /// - Returns: Value clamped to 0.4...1.0.
    static func clampTempoScale(_ scale: Double) -> Double {
        min(1.0, max(0.4, scale))
    }
}

// MARK: - Preview

#Preview("Toolbar — Idle") {
    PlayAlongToolbar(
        playbackState: .idle,
        tempoScale: 1.0,
        isWaitModeEnabled: false,
        isSoundEnabled: true,
        viewMode: .fallingNotes,
        notationMode: .sargam,
        isMIDIConnected: false,
        midiDeviceName: nil,
        latencyPreset: .fast,
        baseBPM: 120,
        onPlayPause: {},
        onStop: {},
        onTempoChange: { _ in },
        onWaitModeToggle: {},
        onSoundToggle: {},
        onViewModeChange: { _ in },
        onNotationModeChange: { _ in },
        onLatencyPresetChange: { _ in }
    )
}

#Preview("Toolbar — MIDI Connected") {
    PlayAlongToolbar(
        playbackState: .playing,
        tempoScale: 0.75,
        isWaitModeEnabled: true,
        isSoundEnabled: false,
        viewMode: .scrollingSheet,
        notationMode: .dual,
        isMIDIConnected: true,
        midiDeviceName: "Yamaha PSR-400",
        latencyPreset: .balanced,
        baseBPM: 100,
        onPlayPause: {},
        onStop: {},
        onTempoChange: { _ in },
        onWaitModeToggle: {},
        onSoundToggle: {},
        onViewModeChange: { _ in },
        onNotationModeChange: { _ in },
        onLatencyPresetChange: { _ in }
    )
}
