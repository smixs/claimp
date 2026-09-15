import Foundation

/// Общие фикстуры из `Tests/Fixtures/` (положены T0b, см. `Tests/Fixtures/README.md`).
/// Путь считается от `#filePath`, поэтому `Package.swift` менять не нужно.
enum PlaybackFixtures {
    /// Короткий трек, на котором проверяются позиция, перемотка и конец трека.
    static let toneName = "tone.wav"

    static func url(named name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/PlaybackTests
            .deletingLastPathComponent() // Tests
            .appending(path: "Fixtures")
            .appending(path: name)
    }
}
