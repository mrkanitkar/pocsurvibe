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
/// ## Unified renderer signature (T11')
/// Consumes the same canonical inputs as `BarsOnStaffView`,
/// `SargamDualRowView`, and `SplitLaneView`:
///   - `noteEvents: [NoteEvent]` — single source of truth.
///   - `currentTime: TimeInterval` — playback clock.
/// Plus per-renderer specifics (the `Song` for key/time signature lookup,
/// `currentNoteIndex` for auto-scroll, mic / MIDI highlight inputs).
///
/// Per the architectural review §2.4, every play-along renderer must accept
/// the same canonical render data shape — `Song.decoded*` JSON blobs are no
/// longer read here.
///
/// ## Reduce Motion (HIG)
/// When `accessibilityReduceMotion` is on, auto-scroll falls back to discrete
/// note-level advance instead of continuous animated scroll.
/// `SargamRenderer`, `WesternRenderer`, and `StaffNotationRenderer` already
/// branch internally on `@Environment(\.accessibilityReduceMotion)` for their
/// scroll animations, so the discrete-advance behaviour is honoured by them;
/// this view documents and reinforces the contract via its accessibility hint.
/// See [Apple HIG — Motion](https://developer.apple.com/design/human-interface-guidelines/motion).
///
/// ## Hand shape coding (HIG)
/// In standard music notation the right hand is shown on the treble clef and
/// the left hand on the bass clef — staff position itself encodes hand
/// independently of color. The shape-coding rule (RH circle / LH square /
/// chord diamond) introduced for `BarsOnStaffView` and `SplitLaneView` is
/// therefore **auto-satisfied** by this renderer's clef placement.
/// See [Apple HIG — Color](https://developer.apple.com/design/human-interface-guidelines/color).
///
/// ## Why not NotationContainerView?
/// `NotationContainerView` reads `@AppStorage("notationDisplayMode")` on
/// its own, ignoring the `notationMode` argument passed from the toolbar.
/// It also adds a mode-picker and zoom-indicator that are inappropriate
/// for the compact play-along sheet. Rendering the renderers directly here
/// is simpler and correctly honours the toolbar's notation-mode selection.
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
    /// Used here only for key signature, time signature, and tempo —
    /// note data comes from `noteEvents`.
    let song: Song

    /// Canonical timed note events (T11' unified input).
    let noteEvents: [NoteEvent]

    /// Current playback position in seconds (T11' unified input).
    let currentTime: TimeInterval

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

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

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

    // MARK: - NoteEvent → Legacy Notation Adapter (T11')

    /// Convert canonical `[NoteEvent]` into the legacy `[SargamNote]` shape
    /// expected by `SargamRenderer`.
    ///
    /// Durations are converted from absolute seconds back into beats using the
    /// song's tempo (`SargamNote.duration` is beat-based). The full Swar name
    /// is split back into `(note, modifier)` so existing `SargamNoteView`
    /// rendering paths continue to display the Komal/Tivra prefix correctly.
    private var sargamNotes: [SargamNote] {
        let beatsPerSecond = max(1.0, Double(song.tempo)) / 60.0
        return noteEvents.map { event in
            let split = Self.splitSwarName(event.swarName)
            return SargamNote(
                note: split.base,
                octave: event.octave,
                duration: event.duration * beatsPerSecond,
                modifier: split.modifier
            )
        }
    }

    /// Convert canonical `[NoteEvent]` into the legacy `[WesternNote]` shape
    /// expected by `WesternRenderer` / `StaffNotationRenderer`.
    private var westernNotes: [WesternNote] {
        let beatsPerSecond = max(1.0, Double(song.tempo)) / 60.0
        return noteEvents.map { event in
            WesternNote(
                note: event.westernName,
                duration: event.duration * beatsPerSecond,
                midiNumber: Int(event.midiNote)
            )
        }
    }

    /// Decompose a full Swar name (e.g., "Komal Re", "Tivra Ma", "Sa") into
    /// its `(base, modifier)` parts. Mirrors the inverse of
    /// `NoteEvent.fullSwarName(note:modifier:)`.
    private static func splitSwarName(_ full: String) -> (base: String, modifier: String?) {
        let parts = full.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        if parts.count == 2 {
            return (String(parts[1]), String(parts[0]).lowercased())
        }
        return (full, nil)
    }

    // MARK: - Body

    var body: some View {
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
        .accessibilityHint(
            reduceMotion
                ? "Notation advances note-by-note in step with playback (Reduce Motion)."
                : "Notation auto-scrolls to follow the current note during playback."
        )
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
        noteEvents: [],
        currentTime: 0,
        currentNoteIndex: nil,
        notationMode: .sargam
    )
}

#Preview("Scrolling Sheet — Western") {
    ScrollingSheetView(
        song: Song(title: "Preview Song", tempo: 120),
        noteEvents: [],
        currentTime: 0,
        currentNoteIndex: 3,
        notationMode: .western
    )
}
