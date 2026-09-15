import Foundation

/// Общие фикстуры из Tests/Fixtures/ (положены T0b, см. Tests/Fixtures/README.md).
/// Путь вычисляется от #filePath, поэтому Package.swift менять не нужно.
enum Fixtures {
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/CoreTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures")
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}
