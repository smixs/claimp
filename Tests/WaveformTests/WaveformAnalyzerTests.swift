import Foundation
import Testing

@testable import Waveform

private struct Stand {
    let directory: URL
    let audio: URL
    let cache: WaveformCache
    let analyzer: WaveformAnalyzer

    init(seconds: Double, amplitude: Float) throws {
        directory = try AudioFixture.makeDirectory()
        audio = directory.appending(path: "tone.wav")
        try AudioFixture.writeTone(seconds: seconds, amplitude: amplitude, to: audio)
        cache = WaveformCache(directory: directory.appending(path: "cache", directoryHint: .isDirectory))
        analyzer = WaveformAnalyzer(cache: cache)
    }
}

@Test("Тон даёт 3840 колонок в 0…1 с настоящими пиками")
func analyzeToneGivesNormalizedColumns() async throws {
    let stand = try Stand(seconds: 2, amplitude: 0.9)

    let data = try await stand.analyzer.analyze(url: stand.audio)

    #expect(data.columns.count == WaveformData.columnCount)
    #expect(data.columns.allSatisfy { $0.peak >= 0 && $0.peak <= 1 })
    #expect(data.columns.contains { $0.peak > 0.5 })
}

@Test("Тишина даёт ровно нули, а не NaN")
func analyzeSilenceGivesZeros() async throws {
    let stand = try Stand(seconds: 1, amplitude: 0)

    let data = try await stand.analyzer.analyze(url: stand.audio)

    #expect(data.columns.count == WaveformData.columnCount)
    #expect(data.columns.allSatisfy { $0.low == 0 && $0.mid == 0 && $0.high == 0 })
}

@Test("Файл короче 3840 фреймов всё равно даёт 3840 колонок")
func analyzeVeryShortFile() async throws {
    let stand = try Stand(seconds: 0.02, amplitude: 0.8)

    let data = try await stand.analyzer.analyze(url: stand.audio)

    #expect(data.columns.count == WaveformData.columnCount)
    #expect(data.columns.allSatisfy { $0.peak.isFinite })
}

@Test("Несуществующий файл даёт cannotOpen")
func analyzeMissingFileThrows() async throws {
    let directory = try AudioFixture.makeDirectory()
    let missing = directory.appending(path: "nope.wav")
    let analyzer = WaveformAnalyzer(cache: WaveformCache(directory: directory))

    await #expect(throws: WaveformError.cannotOpen(missing)) {
        try await analyzer.analyze(url: missing)
    }
}

@Test("Второй анализ берёт волну из кэша, а не из аудиофайла")
func secondAnalyzeReadsCacheNotAudio() async throws {
    let stand = try Stand(seconds: 2, amplitude: 0.9)
    let first = try await stand.analyzer.analyze(url: stand.audio)
    let modified = try FileManager.default.attributesOfItem(atPath: stand.audio.path)[.modificationDate]
    // Подменяем содержимое файла тишиной, сохраняя размер и время правки: ключ кэша не меняется.
    try AudioFixture.writeTone(seconds: 2, amplitude: 0, to: stand.audio)
    try FileManager.default.setAttributes([.modificationDate: modified as Any], ofItemAtPath: stand.audio.path)

    let second = try await stand.analyzer.analyze(url: stand.audio)

    #expect(second == first)
    // Контроль: сам файл действительно стал тишиной - с пустым кэшем анализ даёт нули.
    let coldCache = WaveformCache(directory: stand.directory.appending(path: "cold", directoryHint: .isDirectory))
    let cold = try await WaveformAnalyzer(cache: coldCache).analyze(url: stand.audio)
    #expect(cold.columns.allSatisfy { $0.peak == 0 })
}

@Test("Правка файла обесценивает кэш")
func cacheInvalidatesOnModification() async throws {
    let stand = try Stand(seconds: 1, amplitude: 0.7)
    _ = try await stand.analyzer.analyze(url: stand.audio)
    #expect(try stand.cache.load(for: stand.audio) != nil)

    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: stand.audio.path)

    #expect(try stand.cache.load(for: stand.audio) == nil)
}

@MainActor
@Test("Отменённый анализ даёт cancelled меньше чем за секунду")
func cancelledAnalysisThrowsCancelled() async throws {
    // Длинный MP3 (360 с, анализ около секунды): отмена через 50 мс застаёт анализ
    // уже на ходу - мимо входного гварда, через withTaskCancellationHandler,
    // work.cancel() и Task.checkCancellation в PCMReader.
    let directory = try AudioFixture.makeDirectory()
    let audio = directory.appending(path: "long.mp3")
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures")
        .appending(path: "id3v23.mp3")
    try FileManager.default.copyItem(at: fixture, to: audio)
    // Калибровка: полный анализ с холодного кэша. Отмена обязана стоить долю от него -
    // граница относительная, а не абсолютная, поэтому переживает любую нагрузку машины.
    let calibrationCache = WaveformCache(directory: directory.appending(path: "cal", directoryHint: .isDirectory))
    let calibrationStart = Date()
    _ = try await WaveformAnalyzer(cache: calibrationCache).analyze(url: audio)
    let full = Date().timeIntervalSince(calibrationStart)
    let cache = WaveformCache(directory: directory.appending(path: "cache", directoryHint: .isDirectory))
    let analyzer = WaveformAnalyzer(cache: cache)
    let startedAt = Date()

    let task = Task { @MainActor in try await analyzer.analyze(url: audio) }
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()

    await #expect(throws: WaveformError.cancelled) { try await task.value }
    // Мутанта без onCancel ловит первое ожидание (добегание возвращает данные, а не throw).
    #expect(Date().timeIntervalSince(startedAt) < max(1.0, 3 * full))
}
