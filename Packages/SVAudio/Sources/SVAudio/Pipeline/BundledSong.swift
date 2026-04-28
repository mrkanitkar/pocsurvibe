import Foundation

/// One bundled audition song. `id` is the resource base name shared by the
/// `.mxl` (MusicXML zip) file in `Bundle.main`. The audition pipeline renders
/// the `.mxl` through Verovio at song-selection time.
public struct BundledSong: Identifiable, Hashable, Sendable {
    /// Resource base name in `Bundle.main` (no extension). Matches the
    /// `forResource:` argument used in `Bundle.main.url(forResource:withExtension:)`.
    public let id: String

    /// Display label shown in the segmented picker.
    public let displayName: String

    public init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// All bundled songs, in segmented-picker order.
    public static let all: [BundledSong] = [
        BundledSong(id: "james-bond-theme", displayName: "James Bond Theme"),
        BundledSong(id: "Sukhkarta_Dukhharta", displayName: "Sukhkarta Dukhharta"),
    ]
}
