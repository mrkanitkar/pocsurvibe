import Foundation

extension Song {
    /// Compute display labels for each candidate learner track.
    ///
    /// Derives labels from `accompanimentInstrumentSummary` (a dot-separated
    /// string like "Harmonium · Tabla · Strings"). Falls back to `["Piano"]`
    /// when no summary is present. The first entry is always "Learner".
    ///
    /// Ported from the deleted `SongDetailViewParts.trackLabels(for:)`.
    ///
    /// - Parameter song: The song to derive labels from.
    /// - Returns: Display labels for each selectable track, in track order.
    static func trackLabels(for song: Song) -> [String] {
        guard let summary = song.accompanimentInstrumentSummary, !summary.isEmpty else {
            return ["Piano"]
        }
        let accompaniment =
            summary
            .split(separator: "·")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return ["Learner"] + accompaniment
    }
}
