// SurVibeTests/TestHelpers/Song+TestInstance.swift
import Foundation
@testable import SurVibe

extension Song {
    /// Build a Song for tests. Uses default-empty values for fields not specified;
    /// caller overrides only what the test cares about.
    static func testInstance(
        slugId: String = "test_song",
        title: String = "Test Song",
        ragaName: String = "",
        tempo: Int = 120,
        difficulty: Int = 1
    ) -> Song {
        Song(
            slugId: slugId,
            title: title,
            difficulty: difficulty,
            ragaName: ragaName,
            tempo: tempo
        )
    }
}
