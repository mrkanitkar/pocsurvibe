import Foundation
import Testing

@testable import SVLearning

struct ImportPipelineTests {

    let pipeline = ImportPipeline()

    // MARK: - Helpers

    func collectResults(from stream: AsyncStream<ImportPipelineResult>) async -> [ImportPipelineResult] {
        var results: [ImportPipelineResult] = []
        for await result in stream {
            results.append(result)
        }
        return results
    }

    // MARK: - Happy Path

    @Test
    func completesWithSargamInput() async throws {
        let input = NotationInput(text: "Sa Re Ga Ma Pa Dha Ni Sa", declaredFormat: .sargam)
        let stream = pipeline.run(
            input: input,
            configuration: ImportConfiguration(
                title: "Test Song",
                artist: "Test",
                language: "hi",
                difficulty: 1,
                category: "folk"
            )
        )
        let results = await collectResults(from: stream)

        let completed = results.compactMap {
            if case .completed(let dto) = $0 { return dto } else { return nil }
        }
        #expect(completed.count == 1)
        #expect(completed[0].title == "Test Song")
        #expect(completed[0].source == "user")
    }

    @Test
    func completesWithWesternInput() async throws {
        let input = NotationInput(text: "C4 D4 E4 F4 G4 A4 B4 C5", declaredFormat: .western)
        let stream = pipeline.run(
            input: input,
            configuration: ImportConfiguration(
                title: "C Major",
                artist: "Test",
                language: "en",
                difficulty: 1,
                category: "classical"
            )
        )
        let results = await collectResults(from: stream)

        let completed = results.compactMap {
            if case .completed(let dto) = $0 { return dto } else { return nil }
        }
        #expect(completed.count == 1)
        #expect(completed[0].title == "C Major")
    }

    @Test
    func emitsProgressUpdates() async throws {
        let input = NotationInput(text: "Sa Re Ga Ma Pa", declaredFormat: .sargam)
        let stream = pipeline.run(
            input: input,
            configuration: ImportConfiguration(
                title: "Test",
                artist: "Test",
                language: "hi",
                difficulty: 1,
                category: "folk"
            )
        )
        let results = await collectResults(from: stream)

        let progressUpdates = results.compactMap {
            if case .progress(let u) = $0 { return u } else { return nil }
        }
        #expect(!progressUpdates.isEmpty)
        // Final progress fraction should be 1.0
        #expect(progressUpdates.last?.fraction == 1.0)
    }

    @Test
    func dtoHasCorrectMetadata() async throws {
        let input = NotationInput(text: "Sa Re Ga Ma Pa Dha Ni", declaredFormat: .sargam)
        let stream = pipeline.run(
            input: input,
            configuration: ImportConfiguration(
                title: "Raag Test",
                artist: "Pandit Test",
                language: "hi",
                difficulty: 3,
                category: "classical"
            )
        )
        let results = await collectResults(from: stream)

        let dto = results.compactMap {
            if case .completed(let d) = $0 { return d } else { return nil }
        }.first
        #expect(dto?.artist == "Pandit Test")
        #expect(dto?.language == "hi")
        #expect(dto?.difficulty == 3)
        #expect(dto?.category == "classical")
    }

    // MARK: - Failure Cases

    @Test
    func failsWithEmptyTitle() async throws {
        let input = NotationInput(text: "Sa Re Ga Ma", declaredFormat: .sargam)
        let stream = pipeline.run(
            input: input,
            configuration: ImportConfiguration(
                title: "   ",
                artist: "Test",
                language: "hi",
                difficulty: 1,
                category: "folk"
            )
        )
        let results = await collectResults(from: stream)

        let failed = results.compactMap {
            if case .failed(let e) = $0 { return e } else { return nil }
        }
        #expect(!failed.isEmpty)
    }

    @Test
    func failsWithEmptyInput() async throws {
        let input = NotationInput(text: "   ", declaredFormat: .sargam)
        let stream = pipeline.run(
            input: input,
            configuration: ImportConfiguration(
                title: "Test",
                artist: "Test",
                language: "hi",
                difficulty: 1,
                category: "folk"
            )
        )
        let results = await collectResults(from: stream)

        let failed = results.compactMap {
            if case .failed(let e) = $0 { return e } else { return nil }
        }
        #expect(!failed.isEmpty)
    }

    @Test
    func failsWithUnknownFormat() async throws {
        let input = NotationInput(text: "hello world", declaredFormat: .unknown)
        let stream = pipeline.run(
            input: input,
            configuration: ImportConfiguration(
                title: "Test",
                artist: "Test",
                language: "hi",
                difficulty: 1,
                category: "folk"
            )
        )
        let results = await collectResults(from: stream)

        let failed = results.compactMap {
            if case .failed(let e) = $0 { return e } else { return nil }
        }
        #expect(!failed.isEmpty)
    }

    // MARK: - Warnings

    @Test
    func warningsGeneratedForMissingKeySignature() async throws {
        let input = NotationInput(text: "Sa Re Ga Ma Pa Dha Ni", declaredFormat: .sargam)
        let stream = pipeline.run(
            input: input,
            configuration: ImportConfiguration(
                title: "Test",
                artist: "Test",
                language: "hi",
                difficulty: 1,
                category: "folk"
            )
        )
        let results = await collectResults(from: stream)

        let warnings = results.compactMap {
            if case .warningsGenerated(let w) = $0 { return w } else { return nil }
        }.flatMap { $0 }
        // Key signature info warning expected (sargam parser doesn't extract key)
        #expect(!warnings.isEmpty)
    }
}
