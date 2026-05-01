import Foundation
import SVAudio
import SVCore
import SwiftData
import os

private let cacheLogger = Logger.survibe(category: "NotationCacheService")

// MARK: - NotationCacheService

/// Caching layer between `PlayAlongViewModel` / `ScrollingSheetView` and
/// `VerovioBridge.render(musicXML:options:)`.
///
/// Verovio's SVG render path takes ~3–5 s on a dense MXL (Sukhkarta,
/// James Bond). This service intercepts the render call, checks for a
/// warm `NotationCache` row keyed by `Song.slugId`, and returns the cached
/// payload on hit — skipping the Verovio round-trip entirely.
///
/// ## Hit/miss/stale semantics
/// | State | Description | Action |
/// |-------|-------------|--------|
/// | Hit | Row exists, `renderParamsRaw` matches | Decompress and return cached pages |
/// | Miss | No row for slug | Run Verovio, insert cache row, return pages |
/// | Stale | Row exists but `renderParamsRaw` differs | Re-run Verovio, overwrite row, return pages |
///
/// All three outcomes are logged to `audio_log.txt` via `PipelineFileLog` for
/// verification that repeated opens skip the render delay.
///
/// ## Thread-safety
/// `@MainActor` — callers live on the main actor (`PlayAlongViewModel`,
/// `ScrollingSheetView` tasks) and `VerovioBridge` is also pinned to
/// `@MainActor` (it wraps C++ state).
@MainActor
final class NotationCacheService {

    // MARK: - Properties

    /// The SwiftData context used for `NotationCache` reads and writes.
    private let modelContext: ModelContext

    /// The Verovio bridge instance used when a cache miss requires a live render.
    private let bridge: VerovioBridge

    // MARK: - Initialization

    /// Create a service backed by the given `ModelContext`.
    ///
    /// A new `VerovioBridge` is created internally for cache-miss renders.
    /// The bridge is `@MainActor`-isolated (wraps C++ Verovio state), so
    /// it is safe to create on the same actor as this service.
    ///
    /// - Parameter modelContext: A `ModelContext` from the app's shared `ModelContainer`.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.bridge = VerovioBridge()
    }

    /// Create a service backed by the given `ModelContext` and a pre-existing `VerovioBridge`.
    ///
    /// Use this overload when you want to share a single `VerovioBridge` instance
    /// across multiple callers to avoid re-loading Verovio's resource bundle.
    ///
    /// - Parameters:
    ///   - modelContext: A `ModelContext` from the app's shared `ModelContainer`.
    ///   - bridge: An existing `VerovioBridge` instance to use for cache-miss renders.
    init(modelContext: ModelContext, bridge: VerovioBridge) {
        self.modelContext = modelContext
        self.bridge = bridge
    }

    // MARK: - Public Methods

    /// Return SVG pages for a song, using a warm cache when available.
    ///
    /// On the first open the method runs a full Verovio render, stores the
    /// result in `NotationCache`, and returns the pages. Subsequent calls
    /// with matching render parameters decompress the cached payload and
    /// return immediately — the `VerovioBridge.render: elapsed=...s` log
    /// line is not emitted on a cache hit.
    ///
    /// - Parameters:
    ///   - slug: `Song.slugId` used as the cache key.
    ///   - musicXML: Complete MusicXML document string (used only on miss).
    ///   - options: Render parameters. Changes here trigger a re-render.
    /// - Returns: Array of SVG page strings (one per Verovio page).
    /// - Throws: `PipelineError` from `VerovioBridge` on cache miss/stale render.
    func svgPages(
        slug: String,
        musicXML: String,
        options: VerovioBridge.RenderOptions = .init()
    ) throws -> [String] {
        let paramsRaw = Self.encodeParams(options)
        let existing = try fetchCache(slug: slug)

        if let cache = existing {
            if cache.renderParamsRaw == paramsRaw, let compressed = cache.svgPagesData {
                // Cache hit — decompress and return
                let pages = try decompressPages(compressed)
                let bytes = compressed.count
                cacheLogger.debug("NOTATION-CACHE hit slug=\(slug, privacy: .public) bytes=\(bytes, privacy: .public)")
                PipelineFileLog.shared.log(
                    "NOTATION-CACHE hit slug=\(slug) bytes=\(bytes)"
                )
                return pages
            } else {
                // Stale — re-render and overwrite
                cacheLogger.info("NOTATION-CACHE stale → repopulated slug=\(slug, privacy: .public)")
                PipelineFileLog.shared.log("NOTATION-CACHE stale → repopulated slug=\(slug)")
                let pages = try renderAndStore(
                    slug: slug,
                    musicXML: musicXML,
                    options: options,
                    paramsRaw: paramsRaw,
                    existingCache: cache
                )
                return pages
            }
        } else {
            // Cache miss — render and insert
            cacheLogger.info("NOTATION-CACHE miss → populated slug=\(slug, privacy: .public)")
            PipelineFileLog.shared.log("NOTATION-CACHE miss → populated slug=\(slug)")
            let pages = try renderAndStore(
                slug: slug,
                musicXML: musicXML,
                options: options,
                paramsRaw: paramsRaw,
                existingCache: nil
            )
            return pages
        }
    }

    // MARK: - Private Methods

    /// Fetch a `NotationCache` row for the given slug, or `nil` when none exists.
    private func fetchCache(slug: String) throws -> NotationCache? {
        var descriptor = FetchDescriptor<NotationCache>(
            predicate: #Predicate { $0.slugId == slug }
        )
        descriptor.fetchLimit = 1
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    /// Run a full Verovio render, compress the pages, and persist to the cache.
    ///
    /// - Parameters:
    ///   - slug: Cache key.
    ///   - musicXML: Input document.
    ///   - options: Render options forwarded to `VerovioBridge`.
    ///   - paramsRaw: Pre-encoded params string (avoids redundant encoding).
    ///   - existingCache: When non-nil, overwrites the existing row (stale path).
    ///                    When nil, inserts a new row (miss path).
    /// - Returns: Decoded SVG page strings for immediate use.
    @discardableResult
    private func renderAndStore(
        slug: String,
        musicXML: String,
        options: VerovioBridge.RenderOptions,
        paramsRaw: String,
        existingCache: NotationCache?
    ) throws -> [String] {
        let renderedScore = try bridge.render(musicXML: musicXML, options: options)
        let pages = renderedScore.svgPages
        let compressed = try compressPages(pages)

        if let cache = existingCache {
            // Overwrite stale row in-place
            cache.svgPagesData = compressed
            cache.renderParamsRaw = paramsRaw
            cache.renderedAt = Date()
        } else {
            // Insert new row
            let newCache = NotationCache(slugId: slug, renderParamsRaw: paramsRaw)
            newCache.svgPagesData = compressed
            newCache.renderedAt = Date()
            modelContext.insert(newCache)
        }

        do {
            try modelContext.save()
        } catch {
            // Non-fatal: the pages are returned regardless; next open retries.
            let msg = error.localizedDescription
            cacheLogger.warning(
                "NOTATION-CACHE save failed slug=\(slug, privacy: .public): \(msg, privacy: .public)"
            )
        }

        return pages
    }

    // MARK: - Compression Helpers

    /// Encode SVG pages to gzip-compressed data.
    ///
    /// Joins pages with a NUL byte sentinel, then compresses with zlib deflate.
    /// SVG text is typically 90%+ compressible so a 2 MB multi-page score
    /// compresses to ~100–200 KB on disk.
    ///
    /// - Parameter pages: SVG page strings from Verovio.
    /// - Returns: Compressed `Data`.
    /// - Throws: `NotationCacheError.compressionFailed` when zlib rejects input.
    private func compressPages(_ pages: [String]) throws -> Data {
        // Join pages with a sentinel separator that cannot appear in SVG XML.
        let joined = pages.joined(separator: "\0")
        guard let raw = joined.data(using: .utf8) else {
            throw NotationCacheError.compressionFailed
        }
        return try (raw as NSData).compressed(using: .zlib) as Data
    }

    /// Decompress gzip-compressed SVG pages data back to strings.
    ///
    /// - Parameter data: Compressed payload produced by `compressPages(_:)`.
    /// - Returns: Array of SVG page strings.
    /// - Throws: `NotationCacheError.decompressionFailed` on corrupt data.
    private func decompressPages(_ data: Data) throws -> [String] {
        let raw: Data
        do {
            raw = try (data as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw NotationCacheError.decompressionFailed
        }
        guard let joined = String(data: raw, encoding: .utf8) else {
            throw NotationCacheError.decompressionFailed
        }
        return joined.components(separatedBy: "\0")
    }

    // MARK: - Params Encoding

    /// Encode `RenderOptions` to a stable, comparable JSON string.
    ///
    /// This is intentionally simple JSON rather than a hashed digest so that
    /// the stored value is human-readable during debugging. The `renderParamsRaw`
    /// comparison in `svgPages(slug:musicXML:options:)` is a plain equality check.
    ///
    /// - Parameter options: Render options to encode.
    /// - Returns: JSON string, e.g. `{"includeLyrics":true}`.
    nonisolated private static func encodeParams(_ options: VerovioBridge.RenderOptions) -> String {
        "{\"includeLyrics\":\(options.includeLyrics)}"
    }
}

// MARK: - NotationCacheError

/// Errors specific to the `NotationCacheService` compression path.
enum NotationCacheError: Error, Equatable {
    /// Zlib compression of SVG pages failed.
    case compressionFailed
    /// Zlib decompression of stored SVG pages failed (corrupt or truncated data).
    case decompressionFailed
}
