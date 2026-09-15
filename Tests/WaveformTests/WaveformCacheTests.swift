import Foundation
import Testing

@testable import Waveform

/// Кэш волны не глотает ошибки (SPEC §6.16): промах - это `nil`, а испорченный или нечитаемый
/// файл - ошибка с причиной наверх, а не молчаливый промах.

/// Файл-трек, от которого считается ключ кэша: без него `fileURL` не построить.
private func audioFile(in directory: URL) throws -> URL {
    let url = directory.appending(path: "tone.wav")
    try AudioFixture.writeTone(seconds: 0.05, amplitude: 0.5, to: url)
    return url
}

@Test("Кэша нет - это промах (nil), а не ошибка: холодный трек просто посчитается")
func missingCacheEntryIsMiss() throws {
    let directory = try AudioFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try audioFile(in: directory)
    let cache = WaveformCache(directory: directory.appending(path: "cache", directoryHint: .isDirectory))

    #expect(try cache.load(for: url) == nil)
}

@Test("Испорченный файл кэша даёт ошибку с причиной, а не молчаливый промах")
func corruptCacheEntryThrows() throws {
    let directory = try AudioFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try audioFile(in: directory)
    let cache = WaveformCache(directory: directory.appending(path: "cache", directoryHint: .isDirectory))
    let file = try #require(cache.fileURL(for: url))
    try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    // Чужой буфер на месте готового кэша: раньше он молча означал «кэша нет».
    var stale = WaveformData(columns: []).encoded()
    stale[4] = 1  // версия за сигнатурой "DJWF"
    try stale.write(to: file)

    #expect(throws: WaveformError.badCache) { try cache.load(for: url) }
}

@Test("Кэш не записался (путь занят файлом) - ошибка наверх, а не тихий пропуск")
func unwritableCacheEntryThrows() throws {
    let directory = try AudioFixture.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try audioFile(in: directory)
    // Папка кэша не создастся: на её месте лежит файл.
    let blocked = directory.appending(path: "cache")
    try Data("not a directory".utf8).write(to: blocked)
    let cache = WaveformCache(directory: blocked)

    #expect(throws: (any Error).self) {
        try cache.store(WaveformData(columns: [WaveformData.Column(low: 0.5, mid: 0.5, high: 0.5)]), for: url)
    }
}
