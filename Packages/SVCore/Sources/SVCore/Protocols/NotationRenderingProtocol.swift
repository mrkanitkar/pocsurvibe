import Foundation

/// Protocol for notation rendering backends.
///
/// Abstracts the display of musical notation so different rendering modes
/// (falling notes, scrolling sheet, staff notation) can share the same
/// data model and scoring interface.
///
/// ## Conformers
/// - `FallingNotesView` — Synthesia-style falling note blocks
/// - `ScrollingSheetView` — horizontal scrolling sargam/western notation
/// - Future: `StaffNotationView` — traditional staff notation
///
/// Each conformer is a SwiftUI view that receives note events and the
/// current playback position, and renders the notation accordingly.
public protocol NotationRenderingProtocol {
    /// The display name for this notation mode (e.g., "Falling Notes").
    var displayName: String { get }

    /// Whether this renderer supports real-time highlighting of the current note.
    var supportsRealtimeHighlight: Bool { get }

    /// Whether this renderer supports zoom/scale adjustments.
    var supportsZoom: Bool { get }

    /// Minimum zoom level (1.0 = default).
    var minimumZoom: Double { get }

    /// Maximum zoom level.
    var maximumZoom: Double { get }
}

/// Default values for notation rendering protocols.
extension NotationRenderingProtocol {
    /// Default: supports real-time highlight.
    public var supportsRealtimeHighlight: Bool { true }

    /// Default: supports zoom.
    public var supportsZoom: Bool { true }

    /// Default minimum zoom.
    public var minimumZoom: Double { 0.5 }

    /// Default maximum zoom.
    public var maximumZoom: Double { 3.0 }
}
