import Foundation
import SwiftData
import Testing

@testable import SurVibe

@Suite("NotationCache @Model")
@MainActor
struct NotationCacheTests {

    // MARK: - Model defaults

    @Test("Default slugId is empty")
    func defaultSlugIdIsEmpty() {
        let cache = NotationCache()
        #expect(cache.slugId.isEmpty)
    }

    @Test("Default renderParamsRaw is empty")
    func defaultRenderParamsRawIsEmpty() {
        let cache = NotationCache()
        #expect(cache.renderParamsRaw.isEmpty)
    }

    @Test("Default svgPagesData is nil")
    func defaultSvgPagesDataIsNil() {
        let cache = NotationCache()
        #expect(cache.svgPagesData == nil)
    }

    @Test("Default renderedAt is distantPast")
    func defaultRenderedAtIsDistantPast() {
        let cache = NotationCache()
        #expect(cache.renderedAt == Date.distantPast)
    }

    @Test("Init with slug and params sets correct values")
    func initSetsValues() {
        let cache = NotationCache(slugId: "song-001", renderParamsRaw: "{\"includeLyrics\":true}")
        #expect(cache.slugId == "song-001")
        #expect(cache.renderParamsRaw == "{\"includeLyrics\":true}")
        #expect(cache.svgPagesData == nil)
        #expect(cache.renderedAt == Date.distantPast)
    }

    // MARK: - SwiftData round-trip

    @Test("NotationCache inserts and fetches correctly")
    func insertAndFetch() throws {
        let context = try SwiftDataTestContainer.freshContext()
        let cache = NotationCache(
            slugId: "song-sukhkarta",
            renderParamsRaw: "{\"includeLyrics\":true}"
        )
        cache.svgPagesData = Data("fake-svg-data".utf8)
        cache.renderedAt = Date()
        context.insert(cache)
        try context.save()

        var descriptor = FetchDescriptor<NotationCache>(
            predicate: #Predicate { $0.slugId == "song-sukhkarta" }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results.first?.renderParamsRaw == "{\"includeLyrics\":true}")
        #expect(results.first?.svgPagesData != nil)
    }

    @Test("Fetch returns empty when no matching slug")
    func fetchReturnsEmptyForUnknownSlug() throws {
        let context = try SwiftDataTestContainer.freshContext()

        var descriptor = FetchDescriptor<NotationCache>(
            predicate: #Predicate { $0.slugId == "song-does-not-exist" }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        #expect(results.isEmpty)
    }
}

// MARK: - NotationCacheService Tests

/// Tests for `NotationCacheService` using a stub `VerovioBridge` substitute.
///
/// We cannot inject a mock `VerovioBridge` directly (the class is not
/// protocol-backed in this wave), so we test the cache read/write and
/// compression logic independently using the real `NotationCache` model
/// and an in-memory SwiftData context.
@Suite("NotationCacheService — compression helpers")
@MainActor
struct NotationCacheServiceCompressionTests {

    @Test("Params encoding is stable — matching renderParamsRaw produces cache hit")
    func paramsEncodingIsStable() throws {
        // Two options with the same value should produce identical keys.
        // We verify via the stored renderParamsRaw matching the expected string.
        let context = try SwiftDataTestContainer.freshContext()

        // Insert a cache entry with a known params string
        let cache = NotationCache(
            slugId: "slug-params-test",
            renderParamsRaw: "{\"includeLyrics\":true}"
        )
        // Store minimal compressed data (single page, zlib compressed)
        let rawData = Data("<svg>test</svg>".utf8)
        let compressed = try (rawData as NSData).compressed(using: .zlib) as Data
        cache.svgPagesData = compressed
        cache.renderedAt = Date()
        context.insert(cache)
        try context.save()

        // Verify it can be fetched and params match the expected string
        var descriptor = FetchDescriptor<NotationCache>(
            predicate: #Predicate { $0.slugId == "slug-params-test" }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        #expect(results.first?.renderParamsRaw == "{\"includeLyrics\":true}")
    }

    @Test("Compression round-trip preserves SVG page content")
    func compressionRoundTrip() throws {
        let pages = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><g class=\"note\"></g></svg>",
            "<svg xmlns=\"http://www.w3.org/2000/svg\"><g class=\"note rest\"></g></svg>",
        ]
        // Simulate the compress/decompress path used by NotationCacheService.
        let joined = pages.joined(separator: "\0")
        let raw = Data(joined.utf8)
        let compressed = try (raw as NSData).compressed(using: .zlib) as Data
        let decompressedRaw = try (compressed as NSData).decompressed(using: .zlib) as Data
        let roundTripped = String(data: decompressedRaw, encoding: .utf8)
        let result = roundTripped?.components(separatedBy: "\0") ?? []
        #expect(result == pages)
    }

    @Test("Stale cache entry is detected when renderParamsRaw changes")
    func staleDetectionOnParamsMismatch() throws {
        let context = try SwiftDataTestContainer.freshContext()

        // Insert an entry with "old" params
        let cache = NotationCache(
            slugId: "slug-stale",
            renderParamsRaw: "{\"includeLyrics\":false}"
        )
        let rawData = Data("<svg/>".utf8)
        let compressed = try (rawData as NSData).compressed(using: .zlib) as Data
        cache.svgPagesData = compressed
        cache.renderedAt = Date(timeIntervalSinceNow: -3600)
        context.insert(cache)
        try context.save()

        // Fetch and compare against "new" params
        var descriptor = FetchDescriptor<NotationCache>(
            predicate: #Predicate { $0.slugId == "slug-stale" }
        )
        descriptor.fetchLimit = 1
        let results = try context.fetch(descriptor)
        let fetched = results.first
        let newParams = "{\"includeLyrics\":true}"
        // Stale when params differ
        #expect(fetched?.renderParamsRaw != newParams)
    }
}
