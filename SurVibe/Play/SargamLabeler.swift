import Foundation

/// Octave indicator relative to the user's chosen Sa pitch.
nonisolated public enum SargamOctave: Hashable, Sendable {
    case doubleLower  // 2 octaves below middle
    case lower  // 1 octave below middle
    case middle  // same octave as Sa
    case upper  // 1 octave above middle
    case doubleUpper  // 2 octaves above middle
}

/// A Sargam syllable with octave indicator and rendering helpers.
nonisolated public struct SargamLabel: Equatable, Sendable {
    /// The Sargam syllable, e.g. `"Sa"`, `"Re♭"`, `"Ma♯"`.
    public let syllable: String
    /// Octave indicator relative to the user's chosen Sa pitch.
    public let octave: SargamOctave

    /// Display string with octave dot (e.g. `"Sa•"` upper, `"•Sa"` lower).
    ///
    /// Doubles the dot for two-octave displacement.
    public var display: String {
        switch octave {
        case .doubleLower: return "••\(syllable)"
        case .lower: return "•\(syllable)"
        case .middle: return syllable
        case .upper: return "\(syllable)•"
        case .doubleUpper: return "\(syllable)••"
        }
    }

    /// VoiceOver-friendly description: e.g. `"Re komal"`, `"Ma tivra"`, `"Sa upper"`.
    ///
    /// Replaces unicode flat/sharp glyphs with spoken `komal`/`tivra` qualifiers and
    /// appends a spoken octave indicator when the note is not in the middle octave.
    public var voiceOverDescription: String {
        let base: String = {
            switch syllable {
            case "Re♭": return "Re komal"
            case "Ga♭": return "Ga komal"
            case "Ma♯": return "Ma tivra"
            case "Dha♭": return "Dha komal"
            case "Ni♭": return "Ni komal"
            default: return syllable
            }
        }()
        switch octave {
        case .doubleLower: return "\(base) two octaves lower"
        case .lower: return "\(base) lower"
        case .middle: return base
        case .upper: return "\(base) upper"
        case .doubleUpper: return "\(base) two octaves upper"
        }
    }
}

/// Maps `(midi, saPitch)` to a Sargam syllable plus octave indicator.
///
/// The mapping uses fixed-do-relative-to-Sa: the chromatic interval from Sa determines
/// the syllable, while MIDI octave distance (in 12-semitone steps) determines the
/// octave dot. This is a pure function; callers are responsible for choosing `saPitch`
/// based on user preference.
nonisolated public enum SargamLabeler {
    private static let syllables = [
        "Sa", "Re♭", "Re", "Ga♭", "Ga",
        "Ma", "Ma♯",
        "Pa",
        "Dha♭", "Dha", "Ni♭", "Ni",
    ]

    /// Returns the Sargam label for a played MIDI note relative to the user's Sa.
    ///
    /// - Parameters:
    ///   - midi: The played MIDI note number (0-127).
    ///   - saPitch: The user's chosen Sa pitch as a MIDI note number.
    /// - Returns: A `SargamLabel` carrying the syllable and octave indicator.
    public static func label(midi: UInt8, saPitch: UInt8) -> SargamLabel {
        let saInt = Int(saPitch)
        let midiInt = Int(midi)
        let semitoneFromSa = ((midiInt - saInt) % 12 + 12) % 12
        let syllable = syllables[semitoneFromSa]

        // Octave distance: how many full 12-semitone octaves are we from Sa,
        // measured by the played MIDI octave's distance from Sa's MIDI octave.
        let saOctave = saInt / 12
        let midiOctave = (midiInt - semitoneFromSa) / 12
        let octaveDelta = midiOctave - saOctave

        let octave: SargamOctave
        switch octaveDelta {
        case ...(-2): octave = .doubleLower
        case -1: octave = .lower
        case 0: octave = .middle
        case 1: octave = .upper
        default: octave = .doubleUpper  // 2+
        }

        return SargamLabel(syllable: syllable, octave: octave)
    }
}
