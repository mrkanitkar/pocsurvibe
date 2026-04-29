import Foundation

/// Time signature for a quantized score.
public enum TimeSignature: String, Sendable, Codable, Hashable, CaseIterable {
    case fourFour = "4/4"
    case threeFour = "3/4"
    case sixEight = "6/8"
    case sevenEight = "7/8"
    case sixteenSixteen = "16/16"

    /// Number of quarter-note beats per measure.
    ///
    /// 6/8 is treated as 3 quarter-note beats (compound duple); 7/8 is treated
    /// as 7 eighth-beats and the quantizer rounds up where needed.
    public var beatsPerMeasure: Int {
        switch self {
        case .fourFour: return 4
        case .threeFour: return 3
        case .sixEight: return 3      // 6 eighths = 3 quarter-note beats
        case .sevenEight: return 7    // we treat as 7 eighth-beats = 3.5 quarter-beats; quantizer rounds up
        case .sixteenSixteen: return 16
        }
    }

    /// MusicXML `<time>` numerator.
    public var numerator: Int {
        switch self {
        case .fourFour: return 4
        case .threeFour: return 3
        case .sixEight: return 6
        case .sevenEight: return 7
        case .sixteenSixteen: return 16
        }
    }

    /// MusicXML `<time>` denominator.
    public var denominator: Int {
        switch self {
        case .fourFour, .threeFour: return 4
        case .sixEight, .sevenEight: return 8
        case .sixteenSixteen: return 16
        }
    }
}

/// Quantization grid resolution.
public enum QuantizeGrid: String, Sendable, Codable, Hashable, CaseIterable {
    case eighth, sixteenth

    /// Grid step in quarter-note beats.
    public var beats: Double { self == .eighth ? 0.5 : 0.25 }
}

/// A single measure of quantized notes.
public struct QuantizedMeasure: Sendable, Codable, Hashable, Equatable {
    public let number: Int
    public let notes: [QuantizedNote]

    /// Creates a quantized measure.
    ///
    /// - Parameters:
    ///   - number: 1-based measure number.
    ///   - notes: Notes contained in this measure.
    public init(number: Int, notes: [QuantizedNote]) {
        self.number = number
        self.notes = notes
    }
}

/// A quantized score — the input to the MusicXML serializer.
public struct QuantizedScore: Sendable, Codable, Hashable, Equatable {
    public let bpm: Int
    public let timeSignature: TimeSignature
    public let measures: [QuantizedMeasure]

    /// Creates a quantized score.
    ///
    /// - Parameters:
    ///   - bpm: Tempo in beats per minute.
    ///   - timeSignature: Time signature for the entire score.
    ///   - measures: Ordered list of measures.
    public init(bpm: Int, timeSignature: TimeSignature, measures: [QuantizedMeasure]) {
        self.bpm = bpm
        self.timeSignature = timeSignature
        self.measures = measures
    }
}
