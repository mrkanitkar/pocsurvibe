import Foundation

/// Factory that builds `RagaContext` instances from raga names.
///
/// Uses the Erv Wilson Persian-North Indian 17-tone reference set (just-intonation
/// frequency ratios) to construct raga scale degrees. Each raga selects 7
/// indices from the 17-tone set, producing a 7-note JI scale.
///
/// The `TuningTable` from AudioKit Microtonality is NOT used at runtime because
/// it is not `Sendable` (NSObject subclass). Instead, the JI ratios are
/// replicated here as static constants and mapped to `Swar` enum cases.
///
/// Reference: Erv Wilson, http://anaphoria.com/genus.pdf
public enum RagaTuningProvider {
    // MARK: - Persian-North Indian 17-Tone Reference Set

    /// Erv Wilson's 17-tone just-intonation reference set for North Indian ragas.
    /// Each value is a frequency ratio relative to Sa (1/1).
    /// Source: AudioKit Microtonality `TuningTable+NorthIndianRaga.swift`.
    private static let referenceSet: [(ratio: Double, index: Int)] = [
        (1.0 / 1.0, 0),            // 0:  Sa              (0¢)
        (135.0 / 128.0, 1),        // 1:  Komal Re (JI)   (~92¢)
        (10.0 / 9.0, 2),           // 2:  Komal Re (alt)  (~182¢) — used in some ragas as Re variant
        (9.0 / 8.0, 3),            // 3:  Re (JI)         (~204¢)
        (1215.0 / 1024.0, 4),      // 4:  Komal Ga (JI)   (~296¢)
        (5.0 / 4.0, 5),            // 5:  Ga (JI)         (~386¢)
        (81.0 / 64.0, 6),          // 6:  Ga (Pyth)       (~408¢)
        (4.0 / 3.0, 7),            // 7:  Ma (JI)         (~498¢)
        (45.0 / 32.0, 8),          // 8:  Tivra Ma (JI)   (~590¢)
        (729.0 / 512.0, 9),        // 9:  Tivra Ma (Pyth) (~612¢)
        (3.0 / 2.0, 10),           // 10: Pa (JI)         (~702¢)
        (405.0 / 256.0, 11),       // 11: Komal Dha (JI)  (~794¢)
        (5.0 / 3.0, 12),           // 12: Dha (JI)        (~884¢)
        (27.0 / 16.0, 13),         // 13: Dha (Pyth)      (~906¢)
        (16.0 / 9.0, 14),          // 14: Komal Ni (JI)   (~996¢)
        (15.0 / 8.0, 15),          // 15: Ni (JI)         (~1088¢)
        (243.0 / 128.0, 16),       // 16: Ni (Pyth)       (~1110¢)
    ]

    // MARK: - Reference-Set Index to Swar Mapping

    /// Map each of the 17 Persian reference-set indices to a Swar case.
    /// Uses cents zones to unambiguously assign each ratio to a swar.
    private static let indexToSwar: [Int: Swar] = [
        0: .sa,
        1: .komalRe,
        2: .komalRe,       // alternative Komal Re ratio (10/9)
        3: .re,
        4: .komalGa,
        5: .ga,
        6: .ga,            // Pythagorean Ga (81/64)
        7: .ma,
        8: .tivraMa,
        9: .tivraMa,       // Pythagorean Tivra Ma (729/512)
        10: .pa,
        11: .komalDha,
        12: .dha,
        13: .dha,          // Pythagorean Dha (27/16)
        14: .komalNi,
        15: .ni,
        16: .ni,           // Pythagorean Ni (243/128)
    ]

    // MARK: - Raga Presets

    /// Raga name → indices into the 17-tone master set.
    /// Matches the AudioKit Microtonality preset methods exactly.
    private static let ragaPresets: [String: [Int]] = [
        // Kalyan thaat
        "Yaman": [0, 3, 5, 8, 10, 12, 15],
        "Kalyan": [0, 3, 5, 8, 10, 12, 15],

        // Bilawal thaat
        "Bilawal": [0, 3, 5, 7, 10, 13, 15],

        // Khamaj thaat
        "Khamaj": [0, 3, 5, 7, 10, 12, 14],

        // Kafi thaat
        "Kafi": [0, 3, 4, 7, 10, 13, 14],
        "Megh Malhar": [0, 3, 4, 7, 10, 13, 14],
        "Miyan Ki Malhar": [0, 3, 4, 7, 10, 13, 14],

        // Asawari thaat
        "Asawari": [0, 3, 4, 7, 10, 11, 14],
        "Bhimpalasi": [0, 3, 4, 7, 10, 11, 14],

        // Bhairav thaat
        "Bhairav": [0, 1, 5, 7, 10, 11, 15],

        // Bhairavi thaat
        "Bhairavi": [0, 1, 4, 7, 10, 11, 14],

        // Marwa thaat
        "Marwa": [0, 1, 5, 8, 10, 12, 15],

        // Purvi thaat
        "Purvi": [0, 1, 5, 8, 10, 11, 15],

        // Todi thaat
        "Todi": [0, 1, 4, 8, 10, 11, 15],

        // Patdeep — Kafi-adjacent
        "Patdeep": [0, 3, 4, 7, 10, 13, 15],
    ]

    // MARK: - Public API

    /// Build a `RagaContext` for the given raga name.
    ///
    /// Returns `nil` if the raga name is empty, unknown, or not in the preset dictionary.
    /// The `TuningTable` is NOT used — ratios come from the static master set.
    ///
    /// - Parameter ragaName: Name of the raga (e.g., "Yaman", "Bhairav").
    /// - Returns: An immutable `RagaContext`, or `nil` if the raga is not recognized.
    public static func context(for ragaName: String) -> RagaContext? {
        let trimmed = ragaName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        guard let indices = ragaPresets[trimmed] else { return nil }

        let degrees = indices.compactMap { index -> RagaScaleDegree? in
            guard index < referenceSet.count,
                  let swar = indexToSwar[index] else { return nil }
            return RagaScaleDegree(swar: swar, ratio: referenceSet[index].ratio)
        }

        guard !degrees.isEmpty else { return nil }

        return RagaContext(ragaName: trimmed, scaleDegrees: degrees)
    }

    /// All supported raga names.
    public static var supportedRagas: [String] {
        Array(ragaPresets.keys).sorted()
    }
}
