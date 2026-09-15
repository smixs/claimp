import Foundation
import Testing

@testable import Waveform

@Test("Колонка - это RMS, а не максимум: синус даёт 0,9/√2, тишина - почти ноль")
func columnsAreRmsNotPeak() throws {
    let directory = try AudioFixture.makeDirectory()
    let url = directory.appending(path: "tone-then-silence.wav")
    // 100 Гц - середина полосы low: разделитель пропускает его без ослабления.
    try AudioFixture.writeTone(
        seconds: 2, amplitude: 0.9, frequency: 100, toneSeconds: 1, to: url)
    let total = try PCMReader.frameCount(of: url)
    // Колонка - ровно секунда: первая внутри синуса, вторая в тишине.
    let framesPerColumn = Int(AudioFixture.sampleRate)

    let levels = try PCMReader.columnLevels(
        url: url, columns: 0..<2, framesPerColumn: framesPerColumn, totalFrames: total)

    #expect(abs(levels.low[0] - 0.636) < 0.02)  // 0,9/√2 ≈ 0,636; максимум модуля дал бы 0,9
    #expect(levels.low[0] < 0.8)
    #expect(levels.low[1] < 0.01)
    #expect(levels.mid[1] < 0.01 && levels.high[1] < 0.01)
}

@Test("Битый хвост файла даёт cannotRead с URL и позицией, а не тишину")
func truncatedFileThrowsCannotRead() throws {
    let directory = try AudioFixture.makeDirectory()
    let cut = directory.appending(path: "cut.mp3")
    let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Fixtures")
        .appending(path: "id3v23.mp3")
    try Data(Data(contentsOf: fixture).prefix(1_000_000)).write(to: cut)
    let total = try PCMReader.frameCount(of: cut)
    let framesPerColumn = max(1, total / WaveformData.columnCount)
    do {
        _ = try PCMReader.columnLevels(
            url: cut,
            columns: 0..<WaveformData.columnCount,
            framesPerColumn: framesPerColumn,
            totalFrames: total)
        Issue.record("ожидалась ошибка на битом хвосте, анализ прошёл молча")
    } catch let WaveformError.cannotRead(url, frame) {
        #expect(url == cut)
        // Позиция за нулем: реальные данные прочитались, сбой именно на хвосте.
        #expect(frame > 0)
        #expect(frame < total)
    } catch {
        Issue.record("не та ошибка на битом хвосте: \(error)")
    }
}
