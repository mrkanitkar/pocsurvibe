import Foundation
import Testing

@testable import SVAudio

@Suite("CalibrationResult")
struct CalibrationResultTests {

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = CalibrationResult(
            medianOffsetSeconds: 0.015,
            standardDeviationSeconds: 0.005,
            sampleCount: 14,
            deviceName: "Test Piano",
            deviceID: 42
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CalibrationResult.self, from: data)

        #expect(decoded.medianOffsetSeconds == 0.015)
        #expect(decoded.standardDeviationSeconds == 0.005)
        #expect(decoded.sampleCount == 14)
        #expect(decoded.deviceName == "Test Piano")
        #expect(decoded.deviceID == 42)
    }

    @Test("save and load per device")
    func saveAndLoad() {
        let result = CalibrationResult(
            medianOffsetSeconds: 0.020,
            standardDeviationSeconds: 0.003,
            sampleCount: 16,
            deviceID: 99999
        )
        result.save(for: 99999)

        let loaded = CalibrationResult.load(for: 99999)
        #expect(loaded != nil)
        #expect(loaded?.medianOffsetSeconds == 0.020)
        #expect(loaded?.sampleCount == 16)

        // Cleanup
        CalibrationResult.remove(for: 99999)
        #expect(CalibrationResult.load(for: 99999) == nil)
    }

    @Test("load returns nil for unknown device")
    func loadUnknownDevice() {
        #expect(CalibrationResult.load(for: -99999) == nil)
    }

    @Test("remove clears stored data")
    func removeClearsData() {
        let result = CalibrationResult(
            medianOffsetSeconds: 0.010,
            standardDeviationSeconds: 0.002,
            sampleCount: 12,
            deviceID: 88888
        )
        result.save(for: 88888)
        #expect(CalibrationResult.load(for: 88888) != nil)

        CalibrationResult.remove(for: 88888)
        #expect(CalibrationResult.load(for: 88888) == nil)
    }

    @Test("default timestamp is approximately now")
    func defaultTimestamp() {
        let before = Date()
        let result = CalibrationResult(
            medianOffsetSeconds: 0,
            standardDeviationSeconds: 0,
            sampleCount: 0
        )
        let after = Date()
        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }

    @Test("Equatable conformance")
    func equatable() {
        let a = CalibrationResult(
            medianOffsetSeconds: 0.015,
            standardDeviationSeconds: 0.005,
            sampleCount: 14,
            timestamp: Date(timeIntervalSince1970: 1000)
        )
        let b = CalibrationResult(
            medianOffsetSeconds: 0.015,
            standardDeviationSeconds: 0.005,
            sampleCount: 14,
            timestamp: Date(timeIntervalSince1970: 2000)
        )
        // Different explicit timestamps make them unequal
        #expect(a != b)
    }
}
