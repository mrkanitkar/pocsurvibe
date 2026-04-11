import SVAudio
import SVCore
import SwiftUI

/// Practice tab with real-time pitch detection.
/// Detects notes played on a piano/keyboard via microphone and displays
/// both Indian (Swar) and Western note names with tuning accuracy.
struct PracticeTab: View {
    @State private var viewModel = PitchDetectionViewModel()
    @State private var isLatchingEnabled = false
    @AppStorage("visualizationMode") private var visualizationModeRaw: String = VisualizationMode.tuner.rawValue
    @State private var keyboardLayout: KeyboardLayoutMode = .piano
    @Environment(\.openURL) private var openURL

    /// Current visualization mode, derived from persisted raw value.
    private var visualizationMode: VisualizationMode {
        VisualizationMode(rawValue: visualizationModeRaw) ?? .tuner
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.micStatus == .denied {
                    micDeniedView
                } else if let error = viewModel.errorMessage {
                    errorView(error)
                } else {
                    pitchDetectionView
                }
            }
            .navigationTitle("Pitch Detection")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Mode", selection: $viewModel.detectionMode) {
                        ForEach(DetectionMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .accessibilityLabel("Detection mode")
                    .accessibilityHint("Choose between melody, chord, or both detection modes")
                    .onChange(of: viewModel.detectionMode) { _, _ in
                        if viewModel.isListening {
                            viewModel.stopListening()
                            Task { await viewModel.startListening() }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: Spacing.sm) {
                        keyboardLayoutToggle
                        latchingControls
                        latencyMenu
                        Button {
                            if viewModel.isListening {
                                viewModel.stopListening()
                            } else {
                                Task { await viewModel.startListening() }
                            }
                        } label: {
                            Image(
                                systemName: viewModel.isListening
                                    ? "stop.circle.fill" : "mic.circle.fill"
                            )
                            .font(.title2)
                        }
                        .accessibilityLabel(
                            viewModel.isListening ? "Stop listening" : "Start listening"
                        )
                        .accessibilityHint(
                            viewModel.isListening
                                ? "Stops pitch detection"
                                : "Starts listening for piano notes through the microphone"
                        )
                    }
                }
            }
        }
        .task {
            // Guard gate: only auto-start if mic is not denied.
            // Avoids re-triggering permission flow on every tab appearance
            // when the user has already denied microphone access. (M-4)
            guard viewModel.micStatus != .denied else { return }
            await viewModel.startListening()
        }
        .onDisappear {
            viewModel.stopListening()
        }
        .accessibilityLabel(AccessibilityHelper.tabLabel(for: "Practice"))
    }

    // MARK: - Main Pitch Detection View

    private var pitchDetectionView: some View {
        VStack(spacing: 0) {
            VStack(spacing: Spacing.md) {
                if viewModel.isListening {
                    if viewModel.detectionMode != .melody,
                       let chordName = viewModel.chordDisplayName
                    {
                        chordNameDisplay(chordName)
                    }

                    if let result = viewModel.currentResult,
                       viewModel.detectionMode != .chord
                    {
                        activeNoteLabel(result)
                        centsIndicator(result.centsOffset)
                        frequencyDisplay(result)
                    } else if viewModel.detectionMode == .chord,
                              viewModel.currentChordResult == nil
                    {
                        listeningPlaceholder
                    } else if viewModel.currentResult == nil,
                              viewModel.detectionMode != .chord
                    {
                        listeningPlaceholder
                    }

                    if let expression = viewModel.currentExpression,
                       expression.type != .indeterminate,
                       expression.type != .stable
                    {
                        expressionBadge(expression)
                    }
                } else {
                    idlePlaceholder
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)

            // Visualization mode picker
            Picker("Visualization", selection: $visualizationModeRaw) {
                ForEach(VisualizationMode.allCases, id: \.rawValue) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage)
                        .tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)
            .accessibilityLabel("Visualization mode")
            .accessibilityHint("Choose between tuner, waveform, pitch track, or spectrum display")

            // Audio visualization
            AudioVisualizationView(
                mode: visualizationMode,
                currentResult: viewModel.currentResult,
                liveAmplitude: viewModel.liveAmplitude,
                isListening: viewModel.isListening
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.sm)

            Spacer()

            switch keyboardLayout {
            case .piano:
                InteractivePianoView(
                    activeMidiNotes: viewModel.activeMidiNotes,
                    activeCentsOffset: viewModel.currentResult?.centsOffset ?? 0,
                    isLatchingEnabled: isLatchingEnabled
                )
            case .isomorphic:
                IsomorphicSargamView(
                    activeMidiNotes: viewModel.activeMidiNotes,
                    activeCentsOffset: viewModel.currentResult?.centsOffset ?? 0,
                    isLatchingEnabled: isLatchingEnabled
                )
            }

            if viewModel.isListening && !viewModel.recentNotes.isEmpty {
                noteHistory
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, Spacing.sm)
            }

            debugStatusBar
        }
    }

    // MARK: - Debug Status Bar

    /// Shows detector pipeline status at the bottom of the screen.
    private var debugStatusBar: some View {
        VStack(spacing: 2) {
            Divider()

            // Live amplitude meter bar
            GeometryReader { geo in
                let meterWidth = min(
                    geo.size.width,
                    geo.size.width * viewModel.liveAmplitude * 10
                )
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        viewModel.liveAmplitude > 0.01
                            ? Color.green : Color.gray.opacity(0.3)
                    )
                    .frame(width: max(2, meterWidth), height: 4)
                    .animation(.linear(duration: 0.05), value: viewModel.liveAmplitude)
            }
            .frame(height: 4)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.xs)

            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(viewModel.isListening ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(viewModel.debugStatus)
                    .font(.caption2)
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer()
                Text("amp: \(String(format: "%.4f", viewModel.liveAmplitude))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                if viewModel.detectionCount > 0 {
                    Text("|\(viewModel.detectionCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
        .background(.ultraThinMaterial)
    }
}

// MARK: - Sub-Views & Helpers

private extension PracticeTab {
    /// Compact note label showing Western name, octave, and Swar name.
    func activeNoteLabel(_ result: PitchResult) -> some View {
        HStack(spacing: Spacing.sm) {
            Text("\(viewModel.westernNoteName)\(result.octave)")
                .font(.title).fontWeight(.bold).fontDesign(.rounded)
                .foregroundStyle(centsColor(result.centsOffset))
                .contentTransition(.numericText())
            Text("—").font(.title2).foregroundStyle(.tertiary)
            Text(result.noteName).font(.title2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(viewModel.westernNoteName) \(result.octave), \(AccessibilityHelper.swarLabel(for: result.noteName))"
        )
        .accessibilityValue(AccessibilityHelper.pitchAccuracyLabel(centsOffset: result.centsOffset))
    }

    /// Visual tuner-style indicator showing how sharp or flat the note is.
    func centsIndicator(_ cents: Double) -> some View {
        VStack(spacing: Spacing.xs) {
            GeometryReader { geo in
                let width = geo.size.width
                let center = width / 2
                let clampedCents = max(-50, min(50, cents))
                let offset = (clampedCents / 50.0) * (width / 2) * 0.9
                ZStack {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(height: 8)
                    Rectangle().fill(.secondary).frame(width: 2, height: 16).position(x: center, y: 8)
                    Circle().fill(centsColor(cents)).frame(width: 16, height: 16)
                        .position(x: center + offset, y: 8)
                }
            }
            .frame(height: 20)
            HStack {
                Text("Flat").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(centsText(cents)).font(.caption).fontWeight(.medium).foregroundStyle(centsColor(cents))
                Spacer()
                Text("Sharp").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AccessibilityHelper.pitchAccuracyLabel(centsOffset: cents))
    }

    /// Shows frequency and confidence values.
    func frequencyDisplay(_ result: PitchResult) -> some View {
        HStack(spacing: Spacing.xl) {
            statItem(value: String(format: "%.1f Hz", result.frequency),
                     label: "Frequency", voiceOver: "Frequency \(Int(result.frequency)) hertz")
            statItem(value: "\(Int(result.confidence * 100))%",
                     label: "Confidence", voiceOver: "Confidence \(Int(result.confidence * 100)) percent")
            statItem(value: String(format: "%.3f", result.amplitude),
                     label: "Amplitude", voiceOver: "Amplitude \(Int(result.amplitude * 100)) percent")
        }
    }

    /// A single stat item with monospaced value and label.
    func statItem(value: String, label: String, voiceOver: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOver)
    }

    /// Rolling list of recently detected notes.
    var noteHistory: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent Notes").font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(viewModel.recentNotes.reversed()) { note in
                        VStack(spacing: 2) {
                            Text(verbatim: note.westernName).font(.headline).fontWeight(.semibold)
                            Text(verbatim: note.swarName).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(centsColor(note.centsOffset).opacity(0.15))
                        )
                        .accessibilityLabel("\(note.westernName), \(note.swarName)")
                    }
                }
            }
        }
    }

    /// Shown while listening but no note detected yet.
    var listeningPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "waveform").font(.system(size: 48))
                .foregroundStyle(.secondary).symbolEffect(.variableColor.iterative)
                .accessibilityHidden(true)
            Text("Listening...").font(.title3).foregroundStyle(.secondary)
            Text("Play a note on your piano").font(.subheadline).foregroundStyle(.tertiary)
        }
    }

    /// Shown when the detector is idle.
    var idlePlaceholder: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "pianokeys").font(.system(size: 60))
                .foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Pitch Detection Demo").font(.title2).fontWeight(.semibold)
            Text("Tap the mic button to start detecting notes")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("Play C D E F G A B on your piano", systemImage: "music.note")
                Label("Hold each note for ~1 second", systemImage: "timer")
                Label("See both Western and Swar names", systemImage: "character.textbox")
            }
            .font(.callout).foregroundStyle(.secondary).padding(.top, Spacing.sm)
        }
    }

    /// Shown when microphone permission is denied.
    var micDeniedView: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "mic.slash").font(.system(size: 48))
                .foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Microphone Access Needed").font(.title3).fontWeight(.semibold)
            Text("SurVibe needs microphone access to detect the notes you play.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = viewModel.settingsURL { openURL(url) }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens iOS Settings to enable microphone access")
        }
        .padding(Spacing.lg).frame(maxHeight: .infinity)
    }

    /// Shown when an error occurs.
    func errorView(_ message: String) -> some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 48))
                .foregroundStyle(.orange).accessibilityHidden(true)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Try Again") { Task { await viewModel.startListening() } }
                .buttonStyle(.borderedProminent)
        }
        .padding(Spacing.lg).frame(maxHeight: .infinity)
    }

    /// Large chord name with sargam subtitle when a chord is detected.
    func chordNameDisplay(_ name: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Text(name).font(.title).fontWeight(.bold).fontDesign(.rounded).contentTransition(.numericText())
            if let sargam = viewModel.sargamChordName {
                Text(sargam).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Detected chord: \(name)")
    }

    /// Badge showing pitch expression type (vibrato, meend, gamaka).
    func expressionBadge(_ expression: ExpressionResult) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: expressionIcon(expression.type)).font(.caption)
            Text(expression.type.displayName).font(.caption).fontWeight(.medium)
        }
        .padding(.horizontal, Spacing.sm).padding(.vertical, Spacing.xs)
        .background(Capsule().fill(expressionColor(expression.type).opacity(0.15)))
        .foregroundStyle(expressionColor(expression.type))
        .accessibilityLabel("Expression: \(expression.type.displayName)")
        .accessibilityHint("Current pitch expression detected from your playing")
    }

    /// Toggle between piano and isomorphic sargam keyboard layouts.
    var keyboardLayoutToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                keyboardLayout = keyboardLayout == .piano ? .isomorphic : .piano
            }
        } label: {
            Image(systemName: keyboardLayout.systemImage)
                .font(.title3)
        }
        .accessibilityLabel({
            let target = keyboardLayout == .piano
                ? KeyboardLayoutMode.isomorphic.displayName
                : KeyboardLayoutMode.piano.displayName
            return "Switch to \(target) layout"
        }())
        .accessibilityHint("Toggles between piano and sargam keyboard layouts")
    }

    /// Latching toggle and clear button for chord building mode.
    @ViewBuilder
    var latchingControls: some View {
        Button {
            isLatchingEnabled.toggle()
        } label: {
            Image(systemName: isLatchingEnabled ? "pin.fill" : "pin")
                .font(.title3)
                .foregroundStyle(isLatchingEnabled ? .green : .secondary)
        }
        .accessibilityLabel(isLatchingEnabled ? "Disable latching" : "Enable latching")
        .accessibilityHint("When enabled, tapped keys stay held for chord building")
    }

    /// Toolbar menu for selecting latency preset.
    var latencyMenu: some View {
        Menu {
            ForEach(LatencyPreset.allCases, id: \.self) { preset in
                Button {
                    viewModel.latencyPreset = preset
                    if viewModel.isListening {
                        viewModel.stopListening()
                        Task { await viewModel.startListening() }
                    }
                } label: {
                    HStack {
                        Text(preset.displayName)
                        if preset == viewModel.latencyPreset { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            Image(systemName: "waveform.badge.magnifyingglass").font(.title3)
        }
        .accessibilityLabel("Latency preset")
        .accessibilityHint("Choose detection speed: fast, balanced, or precise")
    }
    /// Color based on tuning accuracy.
    func centsColor(_ cents: Double) -> Color {
        let absCents = abs(cents)
        if absCents < 5 { return .green }
        if absCents < 15 { return .yellow }
        return .orange
    }

    /// Text label for cents offset.
    func centsText(_ cents: Double) -> String {
        let absCents = abs(cents)
        if absCents < 5 { return "In Tune" }
        let direction = cents > 0 ? "sharp" : "flat"
        return "\(Int(absCents))\u{00A2} \(direction)"
    }

    /// SF Symbol name for each expression type.
    func expressionIcon(_ type: ExpressionType) -> String {
        switch type {
        case .vibrato: "waveform.path"
        case .meend: "arrow.right"
        case .gamaka: "waveform"
        case .stable: "equal.circle"
        case .indeterminate: "questionmark.circle"
        }
    }

    /// Color for each expression type.
    func expressionColor(_ type: ExpressionType) -> Color {
        switch type {
        case .vibrato: .blue
        case .meend: .purple
        case .gamaka: .orange
        case .stable: .green
        case .indeterminate: .gray
        }
    }
}

#Preview {
    PracticeTab()
}
