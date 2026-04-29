import Foundation

/// Discrete musical durations in quarter-note beats. Output of the Quantizer.
///
/// Used by `QuantizedNote` to express note length in a way the MusicXML
/// serializer can render to `<type>`, `<dot/>`, and `<time-modification>` elements.
public enum MusicalDuration: String, Sendable, Codable, Hashable, CaseIterable {
    case whole, half, quarter, eighth, sixteenth, thirtySecond
    case dottedHalf, dottedQuarter, dottedEighth, dottedSixteenth
    case tripletQuarter, tripletEighth, tripletSixteenth

    /// Length in quarter-note beats.
    public var beats: Double {
        switch self {
        case .whole: return 4.0
        case .half: return 2.0
        case .quarter: return 1.0
        case .eighth: return 0.5
        case .sixteenth: return 0.25
        case .thirtySecond: return 0.125
        case .dottedHalf: return 3.0
        case .dottedQuarter: return 1.5
        case .dottedEighth: return 0.75
        case .dottedSixteenth: return 0.375
        case .tripletQuarter: return 2.0 / 3.0
        case .tripletEighth: return 1.0 / 3.0
        case .tripletSixteenth: return 1.0 / 6.0
        }
    }

    /// MusicXML `<type>` element value (e.g. "quarter", "eighth", "16th").
    public var musicXMLTypeName: String {
        switch self {
        case .whole: return "whole"
        case .half, .dottedHalf: return "half"
        case .quarter, .dottedQuarter, .tripletQuarter: return "quarter"
        case .eighth, .dottedEighth, .tripletEighth: return "eighth"
        case .sixteenth, .dottedSixteenth, .tripletSixteenth: return "16th"
        case .thirtySecond: return "32nd"
        }
    }

    /// True for dotted variants — emit `<dot/>` in MusicXML.
    public var isDotted: Bool {
        switch self {
        case .dottedHalf, .dottedQuarter, .dottedEighth, .dottedSixteenth: return true
        default: return false
        }
    }

    /// True for triplet variants — emit `<time-modification>` in MusicXML.
    public var isTriplet: Bool {
        switch self {
        case .tripletQuarter, .tripletEighth, .tripletSixteenth: return true
        default: return false
        }
    }
}
