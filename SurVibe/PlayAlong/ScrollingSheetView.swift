import SVAudio
import SVLearning
import SwiftUI

/// Auto-scrolling notation sheet for play-along mode.
///
/// Renders the correct notation renderer for the given `notationMode` and
/// passes `currentNoteIndex` through so each renderer can auto-scroll to
/// the active note. Each renderer (`SargamRenderer`, `WesternRenderer`,
/// `StaffNotationRenderer`) owns its own `ScrollViewReader`, so there is
/// no need for an outer scroll wrapper here.
///
/// Detected pitch is forwarded into `SargamRenderer` so key presses are
/// highlighted on the notation blocks in real time.
///
/// ## Why not NotationContainerView?
/// `NotationContainerView` reads `@AppStorage("notationDisplayMode")` on
/// its own, ignoring the `notationMode` argument passed from the toolbar.
/// It also adds a mode-picker and zoom-indicator that are inappropriate
/// for the compact play-along sheet. Rendering the renderers directly here
/// is simpler and correctly honours the toolbar's notation-mode selection.
///
/// ## Usage
/// ```swift
/// ScrollingSheetView(
///     song: song,
///     currentNoteIndex: viewModel.currentNoteIndex,
///     notationMode: viewModel.notationMode,
///     currentPitch: viewModel.currentPitch,
///     highlightState: viewModel.highlightState
/// )
/// ```
struct ScrollingSheetView: View {
    // MARK: - Properties

    /// Persistent zoom factor applied on top of the active pinch gesture.
    /// Clamped to `0.5...3.0` to mirror `NotationContainerView`.
    @State
    private var zoomScale: CGFloat = 1.0

    /// Live pinch gesture value — multiplies with `zoomScale` during a pinch.
    @GestureState
    private var pinchScale: CGFloat = 1.0

    /// The song whose notation should be displayed.
    let song: Song

    /// Index of the currently playing note, or nil when idle.
    let currentNoteIndex: Int?

    /// Which notation system to display (sargam, western, dual, etc.).
    let notationMode: NotationDisplayMode

    /// Live detected pitch from the microphone, or nil if silent.
    ///
    /// Forwarded into `SargamRenderer` for accuracy-colour highlighting
    /// (with cents badge) when the user sings or plays via mic.
    var currentPitch: PitchResult?

    /// Isolated highlight state observed directly — never through PlayAlongViewModel.
    ///
    /// Passing `HighlightState` here instead of `detectedSwarInfo` means that
    /// note-on/off events only re-render `ScrollingSheetView`, not the entire
    /// `SongPlayAlongView` hierarchy. `SongPlayAlongView.body` must NEVER read
    /// `highlightState`; it is passed directly to this view.
    var highlightState: HighlightState?

    /// Scoring match state of the note at `currentNoteIndex`.
    ///
    /// When `.correct`, notation renders a green border on the active note;
    /// when `.wrong`, a red border. Nil during playback before any user input.
    var currentNoteMatchState: FallingNotesLayoutEngine.NoteState?

    // MARK: - Private Helpers

    /// The effective note name to highlight in the notation, from any input source.
    private var activeDetectedName: String? {
        currentPitch?.noteName ?? highlightState?.detectedSwarInfo?.name
    }

    /// The effective octave to highlight in the notation, from any input source.
    private var activeDetectedOctave: Int? {
        currentPitch?.octave ?? highlightState?.detectedSwarInfo?.octave
    }

    /// Cents offset for the accuracy badge — only meaningful for mic input.
    private var activeDetectedCents: Double {
        currentPitch?.centsOffset ?? 0
    }

    /// The lowest MIDI note number currently pressed on the keyboard, if any.
    ///
    /// Used by `WesternRenderer` and `StaffNotationRenderer` to highlight the
    /// matching notation block in real time. Reads from `HighlightState` directly
    /// so note-on/off events don't trigger `SongPlayAlongView.body` re-renders.
    private var activeDetectedMidiNote: Int? {
        highlightState?.midiHighlightNotes.min()
    }

    // MARK: - Body

    var body: some View {
        let sargamNotes = song.decodedSargamNotes ?? []
        let westernNotes = song.decodedWesternNotes ?? []

        Group {
            switch notationMode {
            case .sargam:
                SargamRenderer(
                    notes: sargamNotes,
                    currentNoteIndex: currentNoteIndex,
                    zoomScale: 1.0,
                    labelOpacity: 1.0,
                    detectedNoteName: activeDetectedName,
                    detectedOctave: activeDetectedOctave,
                    detectedCents: activeDetectedCents,
                    currentNoteMatchState: currentNoteMatchState
                )

            case .western:
                WesternRenderer(
                    notes: westernNotes,
                    currentNoteIndex: currentNoteIndex,
                    zoomScale: 1.0,
                    detectedMidiNote: activeDetectedMidiNote,
                    currentNoteMatchState: currentNoteMatchState
                )

            case .dual:
                VStack(spacing: 16) {
                    SargamRenderer(
                        notes: sargamNotes,
                        currentNoteIndex: currentNoteIndex,
                        zoomScale: 1.0,
                        labelOpacity: 1.0,
                        detectedNoteName: activeDetectedName,
                        detectedOctave: activeDetectedOctave,
                        detectedCents: activeDetectedCents,
                        currentNoteMatchState: currentNoteMatchState
                    )
                    Divider().padding(.horizontal, 16)
                    WesternRenderer(
                        notes: westernNotes,
                        currentNoteIndex: currentNoteIndex,
                        zoomScale: 1.0,
                        detectedMidiNote: activeDetectedMidiNote,
                        currentNoteMatchState: currentNoteMatchState
                    )
                }

            case .sheetMusic:
                StaffNotationRenderer(
                    notes: westernNotes,
                    currentNoteIndex: currentNoteIndex,
                    keySignature: song.keySignatureEnum,
                    timeSignature: song.timeSignatureEnum,
                    zoomScale: 1.0,
                    detectedMidiNote: activeDetectedMidiNote,
                    currentNoteMatchState: currentNoteMatchState
                )

            case .sargamPlusSheet:
                VStack(spacing: 16) {
                    SargamRenderer(
                        notes: sargamNotes,
                        currentNoteIndex: currentNoteIndex,
                        zoomScale: 1.0,
                        labelOpacity: 1.0,
                        detectedNoteName: activeDetectedName,
                        detectedOctave: activeDetectedOctave,
                        detectedCents: activeDetectedCents,
                        currentNoteMatchState: currentNoteMatchState
                    )
                    Divider().padding(.horizontal, 16)
                    StaffNotationRenderer(
                        notes: westernNotes,
                        currentNoteIndex: currentNoteIndex,
                        keySignature: song.keySignatureEnum,
                        timeSignature: song.timeSignatureEnum,
                        zoomScale: 1.0,
                        detectedMidiNote: activeDetectedMidiNote,
                        currentNoteMatchState: currentNoteMatchState
                    )
                }
            }
        }
        .scaleEffect(zoomScale * pinchScale, anchor: .center)
        .gesture(pinchGesture)
        .simultaneousGesture(doubleTapReset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scrolling notation sheet")
        .accessibilityHint("Notation auto-scrolls to follow the current note during playback")
    }

    // MARK: - Gestures

    /// Pinch-to-zoom gesture clamped between 0.5x and 3.0x (matches `NotationContainerView`).
    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { value in
                let newZoom = zoomScale * value
                zoomScale = min(3.0, max(0.5, newZoom))
            }
    }

    /// Double-tap gesture that resets the persistent zoom factor to 1.0.
    private var doubleTapReset: some Gesture {
        TapGesture(count: 2).onEnded {
            zoomScale = 1.0
        }
    }
}

// MARK: - Preview

#Preview("Scrolling Sheet — Sargam") {
    ScrollingSheetView(
        song: Song(title: "Preview Song", tempo: 120),
        currentNoteIndex: nil,
        notationMode: .sargam
    )
}

#Preview("Scrolling Sheet — Western") {
    ScrollingSheetView(
        song: Song(title: "Preview Song", tempo: 120),
        currentNoteIndex: 3,
        notationMode: .western
    )
}
