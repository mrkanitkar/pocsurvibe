import SVLearning
import SwiftUI

/// Container view that manages notation display mode, zoom, and scroll synchronization.
///
/// Supports five display modes (Sargam, Western labels, dual, sheet music,
/// Sargam + sheet music) with persistence via @AppStorage. Includes
/// pinch-to-zoom gesture (0.5x to 3.0x range) and feeds the current note
/// index from playback.
///
/// ## Usage
/// ```swift
/// NotationContainerView(
///     song: song,
///     currentNoteIndex: engine.currentNoteIndex,
///     labelOpacity: fadeManager.labelOpacity
/// )
/// ```
struct NotationContainerView: View {
    // MARK: - Properties

    /// The song whose notation should be displayed.
    let song: Song

    /// Index of the currently playing note, or nil if not playing.
    let currentNoteIndex: Int?

    /// Opacity for Sargam note labels, driven by ``SargamFadeManager``.
    let labelOpacity: Double

    @AppStorage("notationDisplayMode")
    private var displayModeRaw: String =
        NotationDisplayMode.sargam.rawValue
    @State
    private var zoomScale: CGFloat = 1.0
    @GestureState
    private var pinchScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    /// The effective zoom level combining base zoom and active pinch gesture.
    private var effectiveZoom: CGFloat {
        let combined = zoomScale * pinchScale
        return min(3.0, max(0.5, combined))
    }

    /// The current display mode parsed from @AppStorage.
    private var displayMode: NotationDisplayMode {
        NotationDisplayMode(rawValue: displayModeRaw) ?? .sargam
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            modePicker

            notationContent
                .gesture(pinchGesture)

            zoomIndicator
        }
    }

    // MARK: - Private Views

    /// Segmented picker for switching between notation display modes.
    private var modePicker: some View {
        Picker("Notation", selection: $displayModeRaw) {
            ForEach(NotationDisplayMode.allCases, id: \.rawValue) { mode in
                Text(mode.label).tag(mode.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .accessibilityLabel("Notation display mode")
        .accessibilityHint("Choose between Sargam, Western, sheet music, or combined notations")
    }

    /// The notation renderers switched by the current display mode.
    @ViewBuilder
    private var notationContent: some View {
        // T11'-pending: see note in ScrollingSheetView.body — JSON-blob
        // notation source dropped in T5'; renderers will be rewired to
        // consume `[NoteEvent]` in T11'.
        let sargamNotes: [SargamNote] = []
        let westernNotes: [WesternNote] = []

        switch displayMode {
        case .sargam:
            SargamRenderer(
                notes: sargamNotes,
                currentNoteIndex: currentNoteIndex,
                zoomScale: effectiveZoom,
                labelOpacity: labelOpacity
            )

        case .western:
            WesternRenderer(
                notes: westernNotes,
                currentNoteIndex: currentNoteIndex,
                zoomScale: effectiveZoom
            )

        case .dual:
            VStack(spacing: 16) {
                SargamRenderer(
                    notes: sargamNotes,
                    currentNoteIndex: currentNoteIndex,
                    zoomScale: effectiveZoom,
                    labelOpacity: labelOpacity
                )

                Divider()
                    .padding(.horizontal, 16)

                WesternRenderer(
                    notes: westernNotes,
                    currentNoteIndex: currentNoteIndex,
                    zoomScale: effectiveZoom
                )
            }

        case .sheetMusic:
            StaffNotationRenderer(
                notes: westernNotes,
                currentNoteIndex: currentNoteIndex,
                keySignature: song.keySignatureEnum,
                timeSignature: song.timeSignatureEnum,
                zoomScale: effectiveZoom
            )

        case .sargamPlusSheet:
            VStack(spacing: 16) {
                SargamRenderer(
                    notes: sargamNotes,
                    currentNoteIndex: currentNoteIndex,
                    zoomScale: effectiveZoom,
                    labelOpacity: labelOpacity
                )

                Divider()
                    .padding(.horizontal, 16)

                StaffNotationRenderer(
                    notes: westernNotes,
                    currentNoteIndex: currentNoteIndex,
                    keySignature: song.keySignatureEnum,
                    timeSignature: song.timeSignatureEnum,
                    zoomScale: effectiveZoom
                )
            }
        }
    }

    /// Shows the current zoom level when not at default (1.0x).
    @ViewBuilder
    private var zoomIndicator: some View {
        if effectiveZoom != 1.0 {
            Text(String(format: "%.1fx", effectiveZoom))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .accessibilityLabel(
                    "Zoom level \(String(format: "%.1f", effectiveZoom)) times"
                )
        }
    }

    // MARK: - Gestures

    /// Pinch-to-zoom gesture clamped between 0.5x and 3.0x.
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
}
