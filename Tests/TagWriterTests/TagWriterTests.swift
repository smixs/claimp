import Core
import Foundation
import Testing

@testable import TagWriter

/// Фикстуры только читаются (эталон - MD5 в Tests/Fixtures/README.md): запись идёт в копию
/// во временной папке, как в тестах сканера.
private enum Fixtures {
    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/TagWriterTests
            .deletingLastPathComponent() // Tests
            .appendingPathComponent("Fixtures")
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }
}

private final class Sandbox {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("claimp-t22-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func copy(_ fixture: String) throws -> URL {
        let copy = directory.appendingPathComponent(fixture)
        try FileManager.default.copyItem(at: Fixtures.url(fixture), to: copy)
        return copy
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Форматы, у которых есть фикстура. Читателем всегда выступает штатный сканер:
/// запись проверяется тем же путём, каким её увидит плейлист.
private let writableFixtures = ["id3v23.mp3", "id3v24.mp3", "tagged.flac", "tone.wav", "tone.aiff"]

@Test("Записанные BPM и тональность читает штатный сканер", arguments: writableFixtures)
func writtenTagsAreReadBackByScanner(fixture: String) async throws {
    let sandbox = try Sandbox()
    let url = try sandbox.copy(fixture)

    try TagWriter.write(bpm: 174.4, key: "Am", to: url)

    let track = try #require(await LibraryScanner().track(at: url))
    #expect(track.bpm == 174)
    #expect(track.displayBPM == "174")
    #expect(track.key == "Am")
}

@Test("Чужие теги запись не трогает", arguments: ["id3v23.mp3", "tagged.flac"])
func otherTagsSurviveWrite(fixture: String) async throws {
    let sandbox = try Sandbox()
    let url = try sandbox.copy(fixture)

    let before = try #require(await LibraryScanner().track(at: url))
    try TagWriter.write(bpm: 128, key: "F#m", to: url)
    let after = try #require(await LibraryScanner().track(at: url))

    #expect(after.title == before.title)
    #expect(after.artist == before.artist)
    #expect(after.album == before.album)
    #expect(after.year == before.year)
    #expect(after.artwork == before.artwork)
    #expect(after.key == "F#m")
}

@Test("Несуществующий файл - ошибка с путём, файл не создаётся")
func missingFileFails() throws {
    let sandbox = try Sandbox()
    let url = sandbox.directory.appendingPathComponent("no-such-track.mp3")

    #expect(throws: TagWriteFailure.self) {
        try TagWriter.write(bpm: 174, key: "Am", to: url)
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test("Не-аудио файл - ошибка, содержимое не меняется")
func nonAudioFileFails() throws {
    let sandbox = try Sandbox()
    let url = sandbox.directory.appendingPathComponent("notes.txt")
    let payload = Data("not a track".utf8)
    try payload.write(to: url)

    #expect(throws: TagWriteFailure.self) {
        try TagWriter.write(bpm: 174, key: "Am", to: url)
    }
    #expect(try Data(contentsOf: url) == payload)
}

@Test("Файл только для чтения - ошибка, а не тихий пропуск")
func readOnlyFileFails() throws {
    let sandbox = try Sandbox()
    let url = try sandbox.copy("tagged.flac")
    try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

    #expect(throws: TagWriteFailure.self) {
        try TagWriter.write(bpm: 174, key: "Am", to: url)
    }
}

@Test("Темп округляется до целого, мусор в тег не пишется")
func bpmFormatting() {
    #expect(TagWriter.formatted(bpm: 174.4) == "174")
    #expect(TagWriter.formatted(bpm: 173.6) == "174")
    #expect(TagWriter.formatted(bpm: 0) == nil)
    #expect(TagWriter.formatted(bpm: -5) == nil)
    #expect(TagWriter.formatted(bpm: .nan) == nil)
    #expect(TagWriter.formatted(bpm: 1000) == nil)
}

@Test("Пустая тональность - ошибка, чужой тег не стирается")
func emptyKeyFails() throws {
    let sandbox = try Sandbox()
    let url = try sandbox.copy("tagged.flac")

    #expect(TagWriter.trimmed(key: "  ") == nil)
    #expect(throws: TagWriteFailure.self) {
        try TagWriter.write(bpm: nil, key: "   ", to: url)
    }
}

/// Версия ID3v2 - часть чужих тегов: TagLib по умолчанию переписывает 2.3 в 2.4 и выбрасывает
/// кадры, которых в 2.4 нет (TDAT). Вся библиотека владельца - ID3v2.3, менять её нельзя.
@Test(
    "Версия ID3v2 остаётся той же, что была в файле",
    arguments: [("id3v23.mp3", UInt8(3)), ("id3v24.mp3", UInt8(4))])
func id3v2VersionIsPreserved(fixture: String, version: UInt8) throws {
    let sandbox = try Sandbox()
    let url = try sandbox.copy(fixture)

    try TagWriter.write(bpm: 174, key: "Am", to: url)

    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let raw = try handle.read(upToCount: 5)
    let header = try Array(#require(raw))
    #expect(Array(header[0..<3]) == Array("ID3".utf8))
    #expect(header[3] == version)
}
