// Packages/SVAudio/Sources/SVAudio/Playback/MIDISource.swift
import Foundation

/// Source bytes for `MultiChannelEngineProtocol.loadSong(source:)`.
public enum MIDISource: Sendable, Equatable {
    /// Standard MIDI File bytes (.mid).
    case midi(Data)
    /// Raw MusicXML text OR a `.mxl` ZIP container. Auto-detected at load
    /// time via `isLikelyMXLZip(_:)`.
    case musicXML(Data)

    /// True if `data` looks like a `.mxl` ZIP archive (begins with PK\x03\x04).
    public static func isLikelyMXLZip(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[0] == 0x50 && data[1] == 0x4B
            && data[2] == 0x03 && data[3] == 0x04
    }
}
