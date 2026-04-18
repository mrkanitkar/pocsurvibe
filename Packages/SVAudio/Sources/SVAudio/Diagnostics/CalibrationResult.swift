import Foundation

/// Result of a latency calibration session for a specific MIDI device.
///
/// Stores the measured systematic offset between metronome beats and user taps.
/// Persisted per-device in UserDefaults keyed by `deviceID` (MIDIUniqueID).
/// Positive offset means the player's tap arrives late relative to the beat
/// (typical for USB/Bluetooth MIDI), requiring subtraction during scoring.
public struct CalibrationResult: Sendable, Codable, Equatable {

    // MARK: - Properties

    /// Median tap offset in seconds. Positive = player taps late.
    public let medianOffsetSeconds: Double

    /// Standard deviation of tap offsets in seconds.
    public let standardDeviationSeconds: Double

    /// Number of valid tap samples used (after outlier removal).
    public let sampleCount: Int

    /// When the calibration was performed.
    public let timestamp: Date

    /// Name of the calibrated device (for display).
    public let deviceName: String?

    /// MIDIUniqueID of the calibrated device (for lookup).
    public let deviceID: Int32?

    // MARK: - Initialization

    public init(
        medianOffsetSeconds: Double,
        standardDeviationSeconds: Double,
        sampleCount: Int,
        timestamp: Date = Date(),
        deviceName: String? = nil,
        deviceID: Int32? = nil
    ) {
        self.medianOffsetSeconds = medianOffsetSeconds
        self.standardDeviationSeconds = standardDeviationSeconds
        self.sampleCount = sampleCount
        self.timestamp = timestamp
        self.deviceName = deviceName
        self.deviceID = deviceID
    }

    // MARK: - Storage

    /// UserDefaults key prefix for per-device calibration.
    private static let keyPrefix = "midi_calibration_"

    /// Save this calibration result for the given device ID.
    public func save(for deviceID: Int32) {
        let key = Self.keyPrefix + String(deviceID)
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// Load the calibration result for a device.
    public static func load(for deviceID: Int32) -> CalibrationResult? {
        let key = keyPrefix + String(deviceID)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CalibrationResult.self, from: data)
    }

    /// Remove stored calibration for a device.
    public static func remove(for deviceID: Int32) {
        let key = keyPrefix + String(deviceID)
        UserDefaults.standard.removeObject(forKey: key)
    }
}
