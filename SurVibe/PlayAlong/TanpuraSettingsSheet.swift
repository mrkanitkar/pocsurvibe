import SwiftUI
import UIKit

/// Bottom sheet for configuring the tanpura drone.
///
/// Two-way binds the master toggle, Sa pitch class, octave, cents offset,
/// and volume on the supplied `TanpuraController`. The caller supplies
/// `canResetToSongDefault` (true when `SongProgress.preferredSaHz != nil`)
/// and the reset handler that clears the override.
///
/// HIG: Sa pitch class uses a Menu-style Picker (12 options; segmented
/// would overflow). Octave uses a 3-item segmented control. Discrete
/// changes trigger `UISelectionFeedbackGenerator`; the toggle uses a
/// light impact.
struct TanpuraSettingsSheet: View {
    @Bindable var controller: TanpuraController
    let canResetToSongDefault: Bool
    let onResetToSongDefault: () -> Void
    /// Called after the Sheet's master Toggle flips the controller state.
    /// Receives the NEW `isTanpuraEnabled` value (post-toggle). Callers use
    /// this to fire a `tanpuraToggled` analytics event with `source: "sheet"`.
    let onToggleAnalytics: ((Bool) -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(
        controller: TanpuraController,
        canResetToSongDefault: Bool,
        onResetToSongDefault: @escaping () -> Void,
        onToggleAnalytics: ((Bool) -> Void)? = nil
    ) {
        self.controller = controller
        self.canResetToSongDefault = canResetToSongDefault
        self.onResetToSongDefault = onResetToSongDefault
        self.onToggleAnalytics = onToggleAnalytics
    }

    private static let pitchClassLabels = [
        "C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Tanpura drone", isOn: Binding(
                        get: { controller.isTanpuraEnabled },
                        set: { _ in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            controller.toggleEnabled()
                            onToggleAnalytics?(controller.isTanpuraEnabled)
                        }
                    ))
                    .accessibilityLabel("Tanpura drone")
                    .accessibilityHint("Turns on a continuous tanpura reference tone")
                }

                Section("Sa") {
                    Picker("Sa", selection: pitchClassBinding) {
                        ForEach(0..<12, id: \.self) { pc in
                            Text("Sa · \(Self.pitchClassLabels[pc])").tag(pc)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Sa pitch class, currently \(Self.pitchClassLabels[controller.saPitchClass])")

                    Picker("Octave", selection: octaveBinding) {
                        ForEach(3...5, id: \.self) { oct in
                            Text("\(oct)").tag(oct)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Sa octave, currently \(controller.saOctave)")
                }

                Section {
                    HStack {
                        Text("Sa offset")
                        Spacer()
                        Text(centsLabel)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Reset") {
                            controller.setCentsOffset(0)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(controller.saCentsOffset == 0)
                        .accessibilityLabel("Reset cents offset to zero")
                    }
                    Slider(
                        value: centsSliderBinding,
                        in: -50...50,
                        step: 1
                    )
                    .accessibilityLabel("Sa offset in cents, adjustable")
                    .accessibilityValue(centsLabel)
                } footer: {
                    Text("Fine-tune Sa in ±50¢ for vocal or harmonium matching.")
                }

                Section("Volume") {
                    Slider(value: volumeBinding, in: 0...1) {
                        Text("Volume")
                    }
                    .accessibilityLabel("Tanpura volume")
                    .accessibilityValue("\(Int(controller.volume * 100))%")
                }

                Section {
                    Button {
                        onResetToSongDefault()
                    } label: {
                        Text("Reset to song default")
                    }
                    .disabled(!canResetToSongDefault)
                    .accessibilityLabel("Reset Sa to song default")
                }
            }
            .navigationTitle("Tanpura")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Bindings

    private var pitchClassBinding: Binding<Int> {
        Binding(
            get: { controller.saPitchClass },
            set: { newValue in
                UISelectionFeedbackGenerator().selectionChanged()
                controller.setSa(pitchClass: newValue, octave: controller.saOctave)
            }
        )
    }

    private var octaveBinding: Binding<Int> {
        Binding(
            get: { controller.saOctave },
            set: { newValue in
                UISelectionFeedbackGenerator().selectionChanged()
                controller.setSa(pitchClass: controller.saPitchClass, octave: newValue)
            }
        )
    }

    private var centsSliderBinding: Binding<Double> {
        Binding(
            get: { Double(controller.saCentsOffset) },
            set: { controller.setCentsOffset(Int($0.rounded())) }
        )
    }

    private var volumeBinding: Binding<Float> {
        Binding(
            get: { controller.volume },
            set: { controller.setVolume($0) }
        )
    }

    private var centsLabel: String {
        let c = controller.saCentsOffset
        if c == 0 { return "0¢" }
        return (c > 0 ? "+\(c)¢" : "\(c)¢")
    }
}

#Preview {
    TanpuraSettingsSheet(
        controller: TanpuraController(),
        canResetToSongDefault: true,
        onResetToSongDefault: {}
    )
}
