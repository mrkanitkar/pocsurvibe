// SurVibe/Play/PlayTab.swift
import SVAudio
import SVCore
import SwiftUI

/// Top-level Play tab view. Free-play surface with instrument picker,
/// live-highlight grand staff, recording strip, and on-screen + MIDI keyboard.
struct PlayTab: View {
    @State
    private var viewModel: PlayTabViewModel = {
        let coord = MIDINoteHighlightCoordinator()
        // Engine and MIDI manager come from singletons; cast to the protocol.
        let engine =
            AudioEngineManager.shared.multiChannel as (any PlayTabAudioEngine)?
            ?? PlaceholderAudioEngine()  // engine missing if startForPlayback hasn't run yet
        let midi = MIDIInputManager.shared as any MIDIInputProviding
        return PlayTabViewModel(engine: engine, midiInput: midi, highlightCoordinator: coord)
    }()

    /// Optional shared guard. ContentView injects the singleton instance so
    /// AppRouter and the toolbar's New-session button speak to the same
    /// guard. Defaulted for previews.
    var scratchpadGuard: UnsavedScratchpadGuard?

    @Environment(AppRouter.self)
    private var router

    @State
    private var isPickerPresented = false
    @State
    private var connectedDeviceNames: [String] = []
    /// Isolated observable holding the display-link-driven highlight set.
    ///
    /// PlayTab.body never reads `highlightState.activeMidiNotes`, so SwiftUI
    /// does NOT re-render PlayTab when the MIDI thread updates the highlight
    /// set. Only `LargePianoView` (which reads the property) re-renders —
    /// matching PlayAlong's scoping path.
    @State
    private var highlightState = PlayTabHighlightState()
    @Environment(\.scenePhase)
    private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            PlayTabToolbar(
                viewModel: viewModel,
                connectedDeviceNames: connectedDeviceNames,
                scratchpadGuard: scratchpadGuard,
                onTapInstrument: { isPickerPresented = true }
            )
            if let banner = viewModel.lastError {
                Text(banner)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange)
            }
            // Staff reads viewModel.saPitch / notationMode internally.
            // Extracted so PlayTab.body never depends on these properties —
            // keypresses no longer invalidate the parent body (which would
            // re-evaluate LargePianoView and slow keypress reflection).
            PlayTabRecordSection(
                viewModel: viewModel,
                highlightState: highlightState
            )
            PlayTabBottomStripContainer(viewModel: viewModel)
            LargePianoView(
                highlightState: highlightState,
                onNoteOn: { midi in
                    viewModel.handleNoteOn(UInt8(midi), velocity: 100, source: .touch)
                },
                onNoteOff: { midi in
                    viewModel.handleNoteOff(UInt8(midi), source: .touch)
                }
            )
            .frame(height: 280)
        }
        .task {
            do {
                try AudioEngineManager.shared.startForPlayback()
                if let realEngine = AudioEngineManager.shared.multiChannel
                    as (any PlayTabAudioEngine)?
                {
                    viewModel.attachEngine(realEngine)
                }
            } catch {
                // VM's onAppear will surface engine failures via lastError.
            }
            // CoreMIDI client/port creation. Idempotent — safe if already started.
            MIDIInputManager.shared.start()
            viewModel.onAppear()
            // Wire the unsaved-scratchpad guard hooks so AppRouter.switchTab(to:)
            // can defer programmatic tab switches when the scratchpad has
            // captured content. Cleared on disappear.
            router.playTabHasUnsavedContent = { [vm = viewModel] in
                vm.scratchpad.hasContent
            }
            router.clearPlayTabScratchpad = { [vm = viewModel] in
                vm.clearScratchpad(programOverride: nil, saOverride: nil)
            }
            router.presentSaveTakeSheet = { [vm = viewModel] in
                vm.saveTakeSheetPresented = true
            }
            // Drive the visual highlight (staff + on-screen keyboard) from
            // the display-link-driven coordinator so MIDI→highlight latency
            // is bounded by display refresh (~8–16 ms) instead of an
            // unbounded `Task { @MainActor }` hop in the bookkeeping path.
            //
            // Capture `highlightState` strongly: only the staff + keyboard
            // observe `activeMidiNotes`, so PlayTab.body is NOT invalidated
            // by writes here. This mirrors PlayAlong's HighlightState path.
            //
            // VM bookkeeping (`activeMidiNotes`, `scratchpad`) is unaffected.
            viewModel.installHighlightObserver { [hs = highlightState] notes in
                hs.activeMidiNotes = notes
            }
            // Poll `connectedDeviceName` every 250ms instead of consuming
            // `connectionStateStream`. Reasons:
            //
            // 1. The stream is single-consumer — if PlayAlong (or any other
            //    feature) is also draining it, our subscriber may never see
            //    the connect/disconnect events.
            // 2. The stream value is `Bool` (connected vs not) and the
            //    actual `connectedDeviceName` is set asynchronously on the
            //    main actor, so reading the property directly is the
            //    source-of-truth path with no extra synchronization.
            //
            // 250ms is fine for badge UX: hot-plug visibility within ~250ms.
            // SwiftUI auto-cancels this task on view disappear.
            while !Task.isCancelled {
                let names = [MIDIInputManager.shared.connectedDeviceName].compactMap { $0 }
                if names != connectedDeviceNames {
                    connectedDeviceNames = names
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        .onDisappear {
            // Don't stop the shared MIDIInputManager — it's owned by the
            // process and other features (Play-Along) may still need it.
            // `viewModel.onDisappear()` clears the onNoteEvent closure.
            viewModel.onDisappear()
            // Drop guard hooks so a now-unmounted PlayTab doesn't keep the
            // VM alive via router-held closures.
            router.playTabHasUnsavedContent = nil
            router.clearPlayTabScratchpad = nil
            router.presentSaveTakeSheet = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background: viewModel.allNotesOff()
            case .active: viewModel.onAppear()
            // .inactive (control-center pull, banner) must NOT kill held notes.
            case .inactive: break
            @unknown default: break
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            InstrumentPickerSheet(currentProgram: viewModel.currentInstrument) { program in
                viewModel.setInstrument(program)
            }
        }
        .overlay(alignment: .top) {
            if viewModel.shouldShowSoftCapBanner {
                SoftCapBanner(
                    onDismiss: {
                        withAnimation {
                            viewModel.softCapBannerDismissed = true
                        }
                    },
                    onSave: { viewModel.saveTakeSheetPresented = true }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    // Auto-dismiss after 6 seconds. Cancelled automatically
                    // when SwiftUI tears the overlay down (e.g. user taps
                    // Dismiss or Save first).
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if !Task.isCancelled {
                        withAnimation {
                            viewModel.softCapBannerDismissed = true
                        }
                    }
                }
            }
        }
        .alert(
            "Maximum length reached",
            isPresented: viewModel.shouldShowHardCapModalBinding
        ) {
            Button("Save take") { viewModel.saveTakeSheetPresented = true }
            Button("Discard", role: .destructive) {
                viewModel.clearScratchpad(programOverride: nil, saOverride: nil)
            }
        } message: {
            Text("You've reached the 5,000-note maximum. Save this take to keep recording.")
        }
    }
}

/// Wraps `PlayTabBottomStrip` with the standard Play tab horizontal padding.
/// The Expanded Timeline Sheet (popup) was removed in favour of the inline
/// Play/Stop button on the bottom strip and the cursor-driven highlight on
/// the live grand staff — there is no longer any reason to stack a sheet on
/// top of the staff.
private struct PlayTabBottomStripContainer: View {
    @Bindable var viewModel: PlayTabViewModel

    var body: some View {
        PlayTabBottomStrip(viewModel: viewModel)
            .padding(.horizontal)
            .padding(.bottom, 4)
    }
}

/// Soft-cap notification surface. Shown as a top overlay when the scratchpad
/// reaches 1500 notes; auto-dismisses after 6 seconds, or immediately when
/// the user taps Dismiss / Save.
private struct SoftCapBanner: View {
    let onDismiss: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Long take")
                    .font(.headline)
                Text("You've recorded 1,500 notes. Save soon to keep going.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Save", action: onSave)
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Open the Save take sheet")
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .imageScale(.medium)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Dismiss")
            .accessibilityHint("Hide this banner")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Staff subview — owns the observation of `saPitch` / `notationMode` and
/// reads the scratchpad's note-tail so frequent scratchpad mutations only
/// invalidate THIS subview, never `PlayTab.body` (which contains the
/// performance-critical `LargePianoView`).
///
/// Reading `viewModel.scratchpad.notes` here registers the dependency at
/// the subview boundary; the @Observable system re-renders this struct on
/// every Phase-2 append, but `PlayTab.body` and `LargePianoView` are
/// untouched.
private struct PlayTabRecordSection: View {
    let viewModel: PlayTabViewModel
    let highlightState: PlayTabHighlightState

    /// Maximum number of recent recorded notes rendered on the live staff.
    /// Lifted from v1's 16 to 200 so long passages keep extending across
    /// the staff (the renderer wraps in its own horizontal `ScrollView`).
    /// 200 keeps `StaffNotationRenderer` layout well under one frame on
    /// iPad Air 4.
    private static let liveStaffTailCount: Int = 200

    var body: some View {
        // Sort by `onTimeSec` so the staff renders notes in chronological
        // order — notes append to scratchpad on note-OFF so chord finger
        // release order would otherwise scramble onset order.
        let tail = Array(viewModel.scratchpad.notes.suffix(Self.liveStaffTailCount))
            .sorted { $0.onTimeSec < $1.onTimeSec }
        // Recording: static path. Body re-renders on every @Observable
        // scratchpad mutation, so notes appear on the staff at their
        // correct time-aligned x positions immediately.
        if viewModel.isInlinePlaying {
            playbackBody(tail: tail)
                .frame(height: Self.liveStaffSectionHeight)
        } else {
            TimelineGrandStaffView(notes: tail, positionSec: nil, isPlaying: false)
                .frame(height: Self.liveStaffSectionHeight)
        }
    }

    /// Animated body used while inline playback is active. `TimelineView`
    /// fires every ~33ms; each tick samples the engine's position and
    /// hands it to `TimelineGrandStaffView` as `positionSec` so the
    /// per-note highlight + sweeping playhead bar both advance in lockstep
    /// with audio. The grand staff renders both clefs on a *shared* time
    /// axis — left-hand and right-hand notes that played simultaneously
    /// appear at the same x.
    @ViewBuilder
    private func playbackBody(tail: [RecordedNote]) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { _ in
            TimelineGrandStaffView(
                notes: tail,
                positionSec: positionSec,
                isPlaying: true
            )
        }
    }

    /// Vertical budget for the live staff section, hosting
    /// `TimelineGrandStaffView` (treble + gap + bass + margins ≈ 200pt
    /// intrinsic). The extra slack lets the staff breathe vs. the bottom
    /// strip / `LargePianoView` underneath.
    private static let liveStaffSectionHeight: CGFloat = 220

    /// Sampled per-frame inside the `TimelineView`; the closure must read
    /// it on every fire so SwiftUI re-evaluates the body and pushes a new
    /// cursor index downstream.
    private var positionSec: TimeInterval {
        viewModel.inlinePlaybackPositionSec
    }
}


/// No-op engine placeholder used only during the brief window before
/// AudioEngineManager.startForPlayback() succeeds.
private final class PlaceholderAudioEngine: PlayTabAudioEngine, @unchecked Sendable {
    @MainActor
    func loadProgram(into index: Int, program: UInt8, isPercussion: Bool) throws {}
    nonisolated func playTouchNote(_ midiNote: UInt8, velocity: UInt8) {}
    nonisolated func stopTouchNote(_ midiNote: UInt8) {}
    nonisolated func stopAllTouchNotes() {}
}

#Preview {
    PlayTab()
}
