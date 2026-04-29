// SurVibe/Play/PlayTabBottomStrip.swift
import SwiftUI

/// Always-on bottom strip for the Play tab.
///
/// Replaces the v1 `RecordingStripView` (16-note count strip, deleted in T6).
/// Subscribes ONLY to scalar derived values on `ScratchpadState` (`noteCount`,
/// `durationSec`, `hasContent`) — never the full `notes` / `sustain` arrays —
/// per the spec §5.2.2 observation-isolation rule. This keeps Phase-2
/// scratchpad mutations from invalidating `PlayTab.body` (which contains the
/// performance-critical `LargePianoView`).
///
/// Tapping the expand affordance flips
/// `viewModel.expandedSheetPresented = true`, which `PlayTab` binds to a sheet
/// presenting the `ExpandedTimelineSheet` (Staff / Waterfall / Notes tabs).
struct PlayTabBottomStrip: View {
    @Bindable var viewModel: PlayTabViewModel

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.scratchpad.hasContent {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
            Text(viewModel.scratchpad.durationSec.formattedAsClock)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "Recording duration \(viewModel.scratchpad.durationSec.formattedAsClock)"
                )
            // Inline playback transport — drives slot 2 sampler and the
            // shared `MIDINoteHighlightCoordinator`, so playback notes
            // light up on the live grand staff + on-screen piano.
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(
                    systemName: viewModel.isInlinePlaying ? "stop.fill" : "play.fill"
                )
            }
            .disabled(!viewModel.scratchpad.hasContent && !viewModel.isInlinePlaying)
            .accessibilityLabel(viewModel.isInlinePlaying ? "Stop playback" : "Play scratchpad")
            Text("\(viewModel.scratchpad.noteCount) notes · scratchpad")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(
                value: Double(viewModel.scratchpad.noteCount),
                total: Double(ScratchpadState.hardCap)
            )
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Scratchpad capacity")
            .accessibilityValue(
                "\(viewModel.scratchpad.noteCount) of \(ScratchpadState.hardCap) notes"
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        // `.glassEffect(.regular, in:)` was found to swallow Button taps on
        // iOS 26 in this layout (the Liquid-Glass overlay sat above the
        // embedded play/stop Button); fall back to a regular material so the
        // tap reliably reaches the button. Visually similar.
        .background(
            RoundedRectangle(cornerRadius: 12).fill(.regularMaterial)
        )
    }
}
