import Foundation
import os
import SVCore
import SwiftUI

/// Pure computation engine for falling notes layout.
///
/// All methods are static and have no side effects, making them
/// trivially testable and safe to call from any isolation context.
/// This engine handles all coordinate math for the falling notes
/// visualization without coupling to SwiftUI rendering.
enum FallingNotesLayoutEngine {

    // MARK: - Logger

    /// Logger for layout engine diagnostics.
    static let logger = Logger.survibe(category: "FallingNotesLayout")

    // MARK: - Note State

    /// Scoring state of a note during play-along.
    ///
    /// Drives visual feedback: color, opacity, and optional glow.
    enum NoteState: Sendable, Equatable {
        /// Note has not yet reached the hit line.
        case upcoming
        /// Note is currently at the hit line (within tolerance window).
        case active
        /// Player hit the correct note at the right time.
        case correct
        /// Player hit the wrong note while this note was active.
        case wrong
        /// Note passed the hit line without being played.
        case missed
    }

    // MARK: - Layout Calculations

    /// Compute pixels per second based on the viewport and visible time window.
    ///
    /// This value converts time-domain positions (seconds) into spatial
    /// positions (points) so that notes scroll at a consistent speed
    /// regardless of device screen size.
    ///
    /// - Parameters:
    ///   - viewportHeight: Total height of the falling notes viewport in points.
    ///   - visibleDuration: Number of seconds of music visible at once.
    /// - Returns: Points per second conversion factor.
    static func pixelsPerSecond(viewportHeight: CGFloat, visibleDuration: TimeInterval) -> CGFloat {
        guard visibleDuration > 0 else { return 0 }
        return viewportHeight / visibleDuration
    }

    /// Compute the Y position for a note at the given playback time.
    ///
    /// Notes fall from top (future) to bottom (past). A note whose
    /// `noteTimestamp` equals `currentTime` appears at the bottom of the
    /// viewport (the "hit line"). Notes in the future appear higher.
    ///
    /// - Parameters:
    ///   - noteTimestamp: Absolute start time of the note in seconds.
    ///   - currentTime: Current playback position in seconds.
    ///   - pixelsPerSecond: Spatial conversion factor from ``pixelsPerSecond(viewportHeight:visibleDuration:)``.
    ///   - viewportHeight: Total height of the falling notes viewport in points.
    /// - Returns: Y offset in points from the top of the viewport.
    static func noteY(
        noteTimestamp: TimeInterval,
        currentTime: TimeInterval,
        pixelsPerSecond: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let timeUntilHit = noteTimestamp - currentTime
        return viewportHeight - timeUntilHit * pixelsPerSecond
    }

    /// Compute the rendered height of a note rectangle.
    ///
    /// Longer notes produce taller rectangles so the player can see
    /// how long to hold. A minimum height ensures short notes remain
    /// visible and tappable.
    ///
    /// - Parameters:
    ///   - duration: Note duration in seconds.
    ///   - pixelsPerSecond: Spatial conversion factor.
    ///   - minimumHeight: Floor height in points. Default is 24.
    /// - Returns: Height of the note rectangle in points.
    static func noteHeight(
        duration: TimeInterval,
        pixelsPerSecond: CGFloat,
        minimumHeight: CGFloat = 24
    ) -> CGFloat {
        max(duration * pixelsPerSecond, minimumHeight)
    }

    /// Determine whether a note is visible within the current viewport.
    ///
    /// Used for viewport culling so only on-screen notes are rendered.
    /// A padding value extends the check region above and below the
    /// viewport to prevent pop-in during fast scrolling.
    ///
    /// - Parameters:
    ///   - noteY: Y position of the note's top edge (from ``noteY(noteTimestamp:currentTime:pixelsPerSecond:viewportHeight:)``).
    ///   - noteHeight: Height of the note rectangle (from ``noteHeight(duration:pixelsPerSecond:minimumHeight:)``).
    ///   - viewportHeight: Total height of the viewport.
    ///   - padding: Extra points beyond the viewport edges to check. Default is 50.
    /// - Returns: `true` if any part of the note is within the padded viewport.
    static func isNoteVisible(
        noteY: CGFloat,
        noteHeight: CGFloat,
        viewportHeight: CGFloat,
        padding: CGFloat = 50
    ) -> Bool {
        let noteBottom = noteY + noteHeight
        let noteTop = noteY
        return noteBottom > -padding && noteTop < viewportHeight + padding
    }

    /// Natural (white-key) chromatic offsets within an octave (0 = C).
    ///
    /// Used by the fallback geometry calculation to distinguish white keys
    /// from black keys when `keyPositions` has not yet been populated.
    private static let naturalOffsets: Set<Int> = [0, 2, 4, 5, 7, 9, 11]

    /// Build an O(1) lookup map from MIDI note number to center-X position.
    ///
    /// AUD-027: Build once when `keyPositions` changes (in `FallingNotesView.onChange`).
    /// Each `noteX(midiNote:keyPositionMap:viewWidth:)` call then does a dictionary
    /// lookup instead of an O(n) linear scan.
    ///
    /// - Parameter keyPositions: Array of key positions reported by the piano keyboard.
    /// - Returns: Dictionary mapping MIDI note number to center-X in points.
    static func buildKeyPositionMap(_ keyPositions: [KeyPosition]) -> [UInt8: CGFloat] {
        Dictionary(uniqueKeysWithValues: keyPositions.map { ($0.midiNote, $0.centerX) })
    }

    /// Find the horizontal center X position for a MIDI note using a pre-built map.
    ///
    /// AUD-027: O(1) dictionary lookup replaces the O(n) `first(where:)` scan.
    /// Falls back to geometric approximation when the map is empty (first render).
    ///
    /// - Parameters:
    ///   - midiNote: MIDI note number to locate.
    ///   - keyPositionMap: Pre-built map from `buildKeyPositionMap(_:)`.
    ///   - viewWidth: Canvas width in points, used for the fallback calculation.
    /// - Returns: Center X of the matching key, or `nil` if out of keyboard range.
    static func noteX(
        midiNote: UInt8,
        keyPositionMap: [UInt8: CGFloat],
        viewWidth: CGFloat = 390
    ) -> CGFloat? {
        // O(1) fast path: use pre-built map.
        if let centerX = keyPositionMap[midiNote] {
            return centerX
        }

        // Fallback: approximate position from standard 61-key piano geometry.
        // Used on the first render before keyPositions arrives via preference.
        let startMIDI = 36  // C2
        let endMIDI   = 96  // C7
        let note = Int(midiNote)
        guard note >= startMIDI && note <= endMIDI else { return nil }

        let whiteKeyCount = (startMIDI...endMIDI)
            .filter { naturalOffsets.contains((($0 - 60) % 12 + 12) % 12) }
            .count
        guard whiteKeyCount > 0 else { return nil }
        let whiteKeyWidth = viewWidth / CGFloat(whiteKeyCount)

        var whiteIndex = 0
        for midi in startMIDI...endMIDI {
            let offset = ((midi - 60) % 12 + 12) % 12
            let isNatural = naturalOffsets.contains(offset)
            if midi == note {
                return isNatural
                    ? (CGFloat(whiteIndex) + 0.5) * whiteKeyWidth
                    : CGFloat(whiteIndex) * whiteKeyWidth
            }
            if isNatural { whiteIndex += 1 }
        }
        return nil
    }

    /// Find the horizontal center X position for a MIDI note.
    ///
    /// - Parameters:
    ///   - midiNote: MIDI note number to locate.
    ///   - keyPositions: Array of key positions from the piano keyboard view.
    ///   - viewWidth: Width of the canvas in points, used for the fallback calculation.
    /// - Returns: Center X of the matching key, or `nil` if the note is outside the keyboard range.
    static func noteX(
        midiNote: UInt8,
        keyPositions: [KeyPosition],
        viewWidth: CGFloat = 390
    ) -> CGFloat? {
        // Fast path: use measured positions once the piano has laid out.
        if let pos = keyPositions.first(where: { $0.midiNote == midiNote }) {
            return pos.centerX
        }

        // Fallback: approximate position from standard 61-key piano geometry.
        let startMIDI = 36  // C2
        let endMIDI   = 96  // C7
        let note = Int(midiNote)
        guard note >= startMIDI && note <= endMIDI else { return nil }

        let whiteKeyCount = (startMIDI...endMIDI)
            .filter { naturalOffsets.contains((($0 - 60) % 12 + 12) % 12) }
            .count
        guard whiteKeyCount > 0 else { return nil }
        let whiteKeyWidth = viewWidth / CGFloat(whiteKeyCount)

        var whiteIndex = 0
        for midi in startMIDI...endMIDI {
            let offset = ((midi - 60) % 12 + 12) % 12
            let isNatural = naturalOffsets.contains(offset)
            if midi == note {
                return isNatural
                    ? (CGFloat(whiteIndex) + 0.5) * whiteKeyWidth
                    : CGFloat(whiteIndex) * whiteKeyWidth
            }
            if isNatural { whiteIndex += 1 }
        }
        return nil
    }

    /// Color for a note based on its scoring state and Swar identity.
    ///
    /// Upcoming and active notes use `SargamColorMap` to show Swar identity
    /// so the player can read approaching notes by color before they arrive.
    /// Scored states (correct/wrong/missed) override the Swar color with
    /// standard traffic-light feedback so results are unambiguous.
    ///
    /// - Upcoming: `SargamColorMap` color at 60% opacity (recognizable, not distracting).
    /// - Active: `SargamColorMap` color at full opacity (bright, high-contrast cue).
    /// - Correct: `.green` (scoring feedback overrides Swar color).
    /// - Wrong: `.red`.
    /// - Missed: `.gray` at 40% opacity.
    ///
    /// - Parameters:
    ///   - state: The scoring state of the note.
    ///   - swarName: The Swar name (e.g. "Sa", "Komal Re", "Tivra Ma") used to
    ///     look up the identity color. Unrecognized names fall back to `.gray`.
    /// - Returns: A `Color` value for rendering.
    static func noteColor(state: NoteState, swarName: String) -> Color {
        switch state {
        case .upcoming: SargamColorMap.color(for: swarName).opacity(0.6)
        case .active: SargamColorMap.color(for: swarName)
        case .correct: Color.green
        case .wrong: Color.red
        case .missed: Color.gray.opacity(0.4)
        }
    }

    /// Label text to display inside a falling note.
    ///
    /// Returns the appropriate note name string based on the
    /// current notation display mode setting.
    ///
    /// - Parameters:
    ///   - swarName: Indian notation name (e.g., "Sa", "Komal Re").
    ///   - westernName: Western notation name (e.g., "C4", "Db4").
    ///   - mode: Current notation display mode preference.
    /// - Returns: The label string to render inside the note.
    static func noteLabel(
        swarName: String,
        westernName: String,
        mode: NotationDisplayMode
    ) -> String {
        switch mode {
        case .sargam, .sargamPlusSheet:
            swarName
        case .western, .sheetMusic:
            westernName
        case .dual:
            "\(swarName)\n\(westernName)"
        }
    }
}
