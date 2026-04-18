import SVAudio
import SwiftUI

/// User-facing latency calibration screen.
///
/// Displays a visual metronome, collects taps, shows progress,
/// and presents the calibration result with Accept/Retry/Reset options.
/// Saves per-device calibration to UserDefaults via `CalibrationResult`.
struct MIDICalibrationView: View {

    // MARK: - State

    @State private var calibrator = LatencyCalibrator()
    @State private var beatPulse = false

    let midiInput: any MIDIInputProviding

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            Text("MIDI Latency Calibration")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap any key on your MIDI keyboard in time with the metronome beats.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            // Visual metronome
            Circle()
                .fill(beatPulse ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 80, height: 80)
                .scaleEffect(beatPulse ? 1.2 : 1.0)
                .animation(.easeOut(duration: 0.15), value: beatPulse)
                .accessibilityLabel("Metronome beat indicator")
                .accessibilityHint("Pulses on each beat")

            // Progress and state display
            stateView

            // Action buttons
            actionButtons
        }
        .padding()
        .navigationTitle("Calibration")
    }

    // MARK: - State View

    @ViewBuilder
    private var stateView: some View {
        switch calibrator.state {
        case .idle:
            Text("Press Start to begin calibration")
                .foregroundStyle(.secondary)

        case .calibrating(let collected, let total):
            VStack(spacing: 8) {
                ProgressView(value: Double(collected), total: Double(total))
                    .accessibilityLabel("Calibration progress")
                    .accessibilityValue("\(collected) of \(total) taps")
                Text("Tap \(collected) of \(total)")
                    .font(.headline)
            }

        case .complete(let result):
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Calibration Complete")
                    .font(.headline)
                Text(
                    "Offset: \(String(format: "%.1f", result.medianOffsetSeconds * 1000))ms"
                )
                .font(.body.monospacedDigit())
                Text(
                    "Precision: \u{00B1}\(String(format: "%.1f", result.standardDeviationSeconds * 1000))ms"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Calibration complete. Offset \(String(format: "%.1f", result.medianOffsetSeconds * 1000)) milliseconds"
            )

        case .error(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        switch calibrator.state {
        case .idle, .error:
            Button("Start Calibration") {
                startCalibration()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Starts playing metronome beats for you to tap along with")

        case .calibrating:
            Button("Cancel") {
                calibrator.reset()
                midiInput.onNoteEvent = nil
            }
            .buttonStyle(.bordered)

        case .complete(let result):
            HStack(spacing: 16) {
                Button("Accept") {
                    acceptCalibration(result)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Saves this calibration offset for your device")

                Button("Retry") {
                    startCalibration()
                }
                .buttonStyle(.bordered)

                Button("Reset to Zero") {
                    calibrator.reset()
                    midiInput.onNoteEvent = nil
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func startCalibration() {
        calibrator.prepare()

        // Wire MIDI tap capture — captures calibrator for @MainActor callback
        let cal = calibrator
        midiInput.onNoteEvent = { event in
            guard event.isNoteOn else { return }
            Task { @MainActor in
                cal.recordTap(midiTimestamp: event.midiTimestamp)
            }
        }
    }

    private func acceptCalibration(_ result: CalibrationResult) {
        midiInput.onNoteEvent = nil

        // Save per-device calibration using the selected device
        if let manager = (midiInput as? MIDIInputManager)?.deviceManager,
            let deviceID = manager.selectedDeviceID,
            let device = manager.availableDevices.first(where: { $0.id == deviceID })
        {
            let saved = CalibrationResult(
                medianOffsetSeconds: result.medianOffsetSeconds,
                standardDeviationSeconds: result.standardDeviationSeconds,
                sampleCount: result.sampleCount,
                deviceName: device.name,
                deviceID: deviceID
            )
            saved.save(for: deviceID)
        }
    }
}
