import Foundation
import SFBAudioEngine
import Testing

@testable import Core

/// Фикстуры в Tests/Fixtures/ тегов BPM и тональности не содержат и не правятся
/// (эталон - MD5 в README). Теги пишутся в копию во временной папке, как в остальных
/// тестах сканера.
private func taggedCopy(of fixture: String, into dir: URL) throws -> URL {
    let copy = dir.appendingPathComponent(fixture)
    try FileManager.default.copyItem(at: Fixtures.url(fixture), to: copy)
    return copy
}

/// Кадр ID3v2.3: идентификатор, размер (обычный big-endian), флаги, Latin-1 текст.
private func id3v23Frame(_ identifier: String, _ text: String) -> Data {
    var payload = Data([0x00])
    payload += text.data(using: .isoLatin1)!
    var frame = Data(identifier.utf8)
    let size = UInt32(payload.count)
    frame += Data([UInt8(size >> 24), UInt8((size >> 16) & 0xFF), UInt8((size >> 8) & 0xFF), UInt8(size & 0xFF)])
    frame += Data([0x00, 0x00])
    return frame + payload
}

/// Целый тег ID3v2.3 с синхробезопасным размером - кладётся перед файлом-фикстурой.
private func id3v23Tag(_ frames: [(String, String)]) -> Data {
    let body = frames.reduce(Data()) { $0 + id3v23Frame($1.0, $1.1) }
    let size = UInt32(body.count)
    var tag = Data("ID3".utf8)
    tag += Data([0x03, 0x00, 0x00])
    tag += Data([
        UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F),
        UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F),
    ])
    return tag + body
}

@Test("BPM и тональность читаются из тегов Xiph (FLAC)")
func bpmAndKeyFromXiphTags() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let url = try taggedCopy(of: "tagged.flac", into: dir)
    let file = try AudioFile(url: url)
    try file.readPropertiesAndMetadata()
    file.metadata.bpm = 174
    file.metadata.additionalMetadata = ["INITIALKEY": "8A"]
    try file.writeMetadata()

    let track = await LibraryScanner().track(at: url)
    #expect(track?.bpm == 174)
    #expect(track?.displayBPM == "174")
    #expect(track?.key == "8A")
}

@Test("BPM и тональность читаются из тегов ID3v2 (MP3, TBPM и TKEY)")
func bpmAndKeyFromID3Tags() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let url = dir.appendingPathComponent("tkey.mp3")
    let source = try Data(contentsOf: Fixtures.url("id3v23.mp3"))
    try (id3v23Tag([("TBPM", "128"), ("TKEY", "Am")]) + source).write(to: url)

    let track = await LibraryScanner().track(at: url)
    #expect(track?.bpm == 128)
    #expect(track?.key == "Am")
}

@Test("Без тегов BPM и тональность пустые, ячейки пустые")
func noTagsGiveEmptyCells() async {
    let track = await LibraryScanner().track(at: Fixtures.url("tone.wav"))
    #expect(track?.bpm == nil)
    #expect(track?.key == nil)
    #expect(track?.displayBPM == "")
    #expect(track?.displayKey == "")
}
