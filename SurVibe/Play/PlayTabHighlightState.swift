// SurVibe/Play/PlayTabHighlightState.swift
import Foundation

/// Isolated observable highlight state for the Play tab.
///
/// Same pattern as PlayAlong's ``HighlightState``: only the staff renderers
/// and the keyboard observe this object, so MIDI-driven highlight changes do
/// NOT invalidate ``PlayTab/body``. This is the difference between matching
/// PlayAlong's sub-frame perceived latency and our previous tab-wide
/// re-render path.
///
/// SwiftUI's `@Observable` macro is dependency-tracked: a view that reads
/// ``activeMidiNotes`` only re-renders when that property changes — the
/// parent `PlayTab` never re-renders on highlight updates because it does
/// not read `.activeMidiNotes`. The only writer is the display-link-driven
/// `MIDINoteHighlightCoordinator` callback, installed via
/// ``PlayTabViewModel/installHighlightObserver(_:)``.
@Observable
@MainActor
final class PlayTabHighlightState {
    /// MIDI note numbers currently highlighted (touch + MIDI).
    var activeMidiNotes: Set<Int> = []
}
