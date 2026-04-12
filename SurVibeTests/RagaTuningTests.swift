import Testing
@testable import SVAudio

@MainActor
struct RagaTuningTests {
    // MARK: - RagaTuningProvider Tests

    @Test func ragaTuningProviderReturnsNilForEmptyName() {
        #expect(RagaTuningProvider.context(for: "") == nil)
    }

    @Test func ragaTuningProviderReturnsNilForWhitespace() {
        #expect(RagaTuningProvider.context(for: "   ") == nil)
    }

    @Test func unknownRagaReturnsNil() {
        #expect(RagaTuningProvider.context(for: "MadeUpRaga") == nil)
    }

    @Test func yamanHasSevenScaleDegreesWithTivraMa() {
        let context = RagaTuningProvider.context(for: "Yaman")
        #expect(context != nil)
        #expect(context?.scaleDegrees.count == 7)
        #expect(context?.ragaName == "Yaman")

        // Yaman must have Tivra Ma (not shuddh Ma)
        let swarNames = context?.scaleDegrees.map(\.swar.rawValue) ?? []
        #expect(swarNames.contains("Tivra Ma"))
        #expect(!swarNames.contains("Ma"))
    }

    @Test func bilawalHasAllShuddhSwars() {
        let context = RagaTuningProvider.context(for: "Bilawal")
        #expect(context != nil)
        #expect(context?.scaleDegrees.count == 7)

        let swarNames = Set(context?.scaleDegrees.map(\.swar.rawValue) ?? [])
        let expectedSwars: Set<String> = [
            "Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni",
        ]
        #expect(swarNames == expectedSwars)
    }

    @Test func bhairavHasKomalReAndKomalDha() {
        let context = RagaTuningProvider.context(for: "Bhairav")
        #expect(context != nil)

        let swarNames = Set(context?.scaleDegrees.map(\.swar.rawValue) ?? [])
        #expect(swarNames.contains("Komal Re"))
        #expect(swarNames.contains("Komal Dha"))
        #expect(!swarNames.contains("Re"))
        #expect(!swarNames.contains("Dha"))
    }

    @Test func kalyanIsSameAsYaman() {
        let yaman = RagaTuningProvider.context(for: "Yaman")
        let kalyan = RagaTuningProvider.context(for: "Kalyan")
        #expect(yaman != nil)
        #expect(kalyan != nil)
        #expect(yaman?.scaleDegrees.count == kalyan?.scaleDegrees.count)

        // Same scale degrees (same ratios)
        let yamanRatios = yaman?.scaleDegrees.map(\.ratio) ?? []
        let kalyanRatios = kalyan?.scaleDegrees.map(\.ratio) ?? []
        for (y, k) in zip(yamanRatios, kalyanRatios) {
            #expect(abs(y - k) < 1e-10)
        }
    }

    @Test func supportedRagasIsNonEmpty() {
        #expect(!RagaTuningProvider.supportedRagas.isEmpty)
        #expect(RagaTuningProvider.supportedRagas.contains("Yaman"))
        #expect(RagaTuningProvider.supportedRagas.contains("Bilawal"))
    }

    // MARK: - RagaContext Tests

    @Test func ragaContextAllowedSwarNames() {
        let context = RagaTuningProvider.context(for: "Yaman")!
        #expect(context.allowedSwarNames.contains("Sa"))
        #expect(context.allowedSwarNames.contains("Tivra Ma"))
        #expect(!context.allowedSwarNames.contains("Ma"))
        #expect(!context.allowedSwarNames.contains("Komal Re"))
    }

    @Test func ragaScaleDegreesCentsAreOrdered() {
        let context = RagaTuningProvider.context(for: "Yaman")!
        let centValues = context.scaleDegrees.map(\.cents)
        for index in 1..<centValues.count {
            #expect(centValues[index] > centValues[index - 1])
        }
    }

    @Test func saCentsIsZero() {
        let context = RagaTuningProvider.context(for: "Yaman")!
        let saDegree = context.scaleDegrees.first { $0.swar == .sa }
        #expect(saDegree != nil)
        #expect(abs(saDegree!.cents) < 0.001)
    }

    @Test func tivraMaJICentsIsNear590() {
        let context = RagaTuningProvider.context(for: "Yaman")!
        let tivraMa = context.scaleDegrees.first { $0.swar == .tivraMa }
        #expect(tivraMa != nil)
        // 45/32 = 590.22¢
        #expect(abs(tivraMa!.cents - 590.22) < 1.0)
    }

    // MARK: - EqualTemperamentMapper Tests

    @Test func equalTempMapperMatchesSwarUtility() throws {
        let mapper = EqualTemperamentMapper()
        // A4 = 440 Hz
        let mapping = try mapper.mapFrequency(440.0, referencePitch: 440.0)
        // A4 should map to Dha (if Sa=C)
        #expect(mapping.noteName == "Dha")
        #expect(mapping.octave == 4)
        #expect(abs(mapping.centsOffset) < 0.1)
        #expect(mapping.isInRaga == nil)
        #expect(mapping.ragaCentsOffset == nil)
    }

    @Test func equalTempMapperAllowsAllNotes() {
        let mapper = EqualTemperamentMapper()
        #expect(mapper.isNoteAllowed("Sa"))
        #expect(mapper.isNoteAllowed("Tivra Ma"))
        #expect(mapper.isNoteAllowed("Komal Re"))
        #expect(mapper.isNoteAllowed("anything"))
    }

    @Test func equalTempMapperMiddleC() throws {
        let mapper = EqualTemperamentMapper()
        // C4 = 261.63 Hz (approximately)
        let mapping = try mapper.mapFrequency(261.63, referencePitch: 440.0)
        #expect(mapping.noteName == "Sa")
        #expect(mapping.octave == 4)
        #expect(abs(mapping.centsOffset) < 1.0)
    }

    // MARK: - RagaAwareMapper Tests

    @Test func ragaAwareMapperSnapsToJITarget() throws {
        let context = RagaTuningProvider.context(for: "Yaman")!
        let mapper = RagaAwareMapper(ragaContext: context)

        // Generate a frequency that is exactly Tivra Ma in JI (45/32 of Sa)
        // C4 = 261.63 Hz, Tivra Ma (JI) = 261.63 * 45/32 ≈ 367.92 Hz
        let saFreq = 261.625_565_300_6
        let tivraMaFreq = saFreq * 45.0 / 32.0

        let mapping = try mapper.mapFrequency(tivraMaFreq, referencePitch: 440.0)
        #expect(mapping.noteName == "Tivra Ma")
        #expect(mapping.isInRaga == true)
        // JI deviation should be very small (< 5¢)
        if let ragaCents = mapping.ragaCentsOffset {
            #expect(abs(ragaCents) < 5.0)
        }
    }

    @Test func outOfRagaNoteIsFlagged() throws {
        let context = RagaTuningProvider.context(for: "Yaman")!
        let mapper = RagaAwareMapper(ragaContext: context)

        // Play shuddh Ma (F4) which is NOT in Yaman (which uses Tivra Ma)
        // F4 in 12ET = 349.23 Hz
        let mapping = try mapper.mapFrequency(349.23, referencePitch: 440.0)
        #expect(mapping.noteName == "Ma")
        #expect(mapping.isInRaga == false)
    }

    @Test func ragaAwareMapperAllowsInRagaNotes() {
        let context = RagaTuningProvider.context(for: "Yaman")!
        let mapper = RagaAwareMapper(ragaContext: context)
        #expect(mapper.isNoteAllowed("Sa"))
        #expect(mapper.isNoteAllowed("Re"))
        #expect(mapper.isNoteAllowed("Ga"))
        #expect(mapper.isNoteAllowed("Tivra Ma"))
        #expect(mapper.isNoteAllowed("Pa"))
        #expect(mapper.isNoteAllowed("Dha"))
        #expect(mapper.isNoteAllowed("Ni"))
    }

    @Test func ragaAwareMapperRejectsOutOfRagaNotes() {
        let context = RagaTuningProvider.context(for: "Yaman")!
        let mapper = RagaAwareMapper(ragaContext: context)
        #expect(!mapper.isNoteAllowed("Ma"))
        #expect(!mapper.isNoteAllowed("Komal Re"))
        #expect(!mapper.isNoteAllowed("Komal Ga"))
    }

    @Test func ragaAwareMapperSaHasSmallDeviation() throws {
        let context = RagaTuningProvider.context(for: "Bilawal")!
        let mapper = RagaAwareMapper(ragaContext: context)

        // Exact Sa frequency (C4)
        let mapping = try mapper.mapFrequency(261.63, referencePitch: 440.0)
        #expect(mapping.noteName == "Sa")
        #expect(mapping.isInRaga == true)
        if let ragaCents = mapping.ragaCentsOffset {
            #expect(abs(ragaCents) < 2.0)
        }
    }
}
