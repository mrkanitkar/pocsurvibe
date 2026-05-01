import Foundation
import SwiftData

// MARK: - NotationCache @Model

/// Sidecar cache for Verovio-rendered SVG pages, keyed by `Song.slugId`.
///
/// Verovio's `render(musicXML:options:)` takes ~3–5 s on a dense MXL such as
/// Sukhkarta or James Bond. This model stores the rendered SVG payload so that
/// repeated opens of the same song can skip the render entirely.
///
/// ## Cache key
/// `slugId` is the primary key. Cache miss is declared when either:
/// - no `NotationCache` row exists for the slug, or
/// - the stored `renderParamsRaw` differs from the current render parameters
///   (e.g., the user changed page width). `NotationCacheService` handles both
///   cases and re-renders + overwrites the stale row.
///
/// ## Storage
/// `svgPagesData` uses `@Attribute(.externalStorage)` so the row stored in
/// the CloudKit-backed SQLite stays small (a few hundred bytes of metadata)
/// while the multi-MB compressed payload lives on disk in the external blob
/// store. This keeps SwiftData queries fast even when the cache holds dozens
/// of songs.
///
/// ## CloudKit compatibility
/// - All fields have explicit default values.
/// - No `@Attribute(.unique)` — CloudKit does not support unique constraints.
/// - `renderParamsRaw` is a `String` (not a `Codable` struct) so CloudKit can
///   sync it directly without a transformer.
@Model
final class NotationCache {
    // MARK: - Properties

    /// Slug identifier that matches `Song.slugId`.
    ///
    /// Used to look up a cache entry during `NotationCacheService.svgPages(for:)`.
    var slugId: String = ""

    /// Compressed SVG-pages payload.
    ///
    /// Stores the gzip-compressed concatenation of every SVG page string
    /// produced by `VerovioBridge.render(musicXML:options:)`. The
    /// `NotationCacheService` compresses on write and decompresses on read.
    /// `nil` when the cache entry has been reserved but not yet populated.
    @Attribute(.externalStorage)
    var svgPagesData: Data?

    /// Verovio render parameters that produced this cache entry.
    ///
    /// Stored as a compact JSON string, e.g.
    /// `{"includeLyrics":true,"pageWidth":null}`. A cache hit is only valid
    /// when this value matches the current render parameters exactly.
    /// Changing any render knob automatically triggers a re-render and
    /// overwrites this field.
    var renderParamsRaw: String = ""

    /// Timestamp of the last successful render.
    ///
    /// Informational — used for diagnostics and potential future TTL eviction.
    var renderedAt: Date = Date.distantPast

    // MARK: - Initialization

    init(slugId: String = "", renderParamsRaw: String = "") {
        self.slugId = slugId
        self.renderParamsRaw = renderParamsRaw
        self.renderedAt = Date.distantPast
    }
}
