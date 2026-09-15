import AVFoundation
import Foundation
import PropertyBased
import Testing

@testable import Waveform

/// Частота сигналов и тестовых файлов: как у фикстур и плеера.
private let sampleRate = 44100.0

/// Синус заданной частоты: чистый тон, по нему видно, в какую полосу он попадает.
private func sine(_ frequency: Double, seconds: Double = 1, amplitude: Float = 0.9) -> [Float] {
    (0..<Int(seconds * sampleRate)).map {
        amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / sampleRate))
    }
}

/// Пик полосы без первых `skip` секунд: переходный процесс фильтра в начале файла не в счёт.
private func peak(_ band: [Float], skippingFirst skip: Double = 0.05) -> Float {
    let from = min(band.count, Int(skip * sampleRate))
    return band[from...].map(abs).max() ?? 0
}

/// Белый шум по фиксированному зерну: спектр плоский, результат воспроизводим.
private func whiteNoise(count: Int, seed: UInt64 = 0x2545_F491_4F6C_DD1D) -> [Float] {
    var state = seed
    return (0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Float(Int32(truncatingIfNeeded: state >> 33)) / Float(Int32.max)
    }
}

/// Тон в WAV-файле: анализатору нужен файл, а не массив.
private func writeTone(_ frequency: Double, seconds: Double, to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings)
    let format = file.processingFormat
    let values = sine(frequency, seconds: seconds)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(values.count))
    else { throw WaveformError.cannotOpen(url) }
    buffer.frameLength = AVAudioFrameCount(values.count)
    let channels = buffer.floatChannelData!
    for (index, value) in values.enumerated() {
        for channel in 0..<Int(format.channelCount) { channels[channel][index] = value }
    }
    try file.write(from: buffer)
}

/// Полосы сигнала: свежий разделитель на каждый вызов, состояние фильтров нулевое.
private func split(_ samples: [Float]) -> (low: [Float], mid: [Float], high: [Float]) {
    BandSplitter(sampleRate: sampleRate).split(samples)
}

/// Файл с тоном и холодный анализатор на него.
private func analyzedTone(
    _ frequency: Double, seconds: Double = 2
) async throws -> WaveformData {
    let directory = try AudioFixture.makeDirectory()
    let url = directory.appending(path: "tone\(Int(frequency)).wav")
    try writeTone(frequency, seconds: seconds, to: url)
    let cache = WaveformCache(directory: directory.appending(path: "cache", directoryHint: .isDirectory))
    return try await WaveformAnalyzer(cache: cache).analyze(url: url)
}

// MARK: - Полосы

@Test("Низ: синус 100 Гц уходит в low, в mid - в 36 раз меньше, в high - в сотни")
func lowBandTakesBass() {
    let bands = split(sine(100))

    #expect(peak(bands.low) > 0.8)  // измерено 0.900
    #expect(peak(bands.low) > 30 * peak(bands.mid))  // измерено 0.900 против 0.0250
    #expect(peak(bands.low) > 100 * peak(bands.high))  // измерено 0.900 против 0.00002
}

@Test("Середина: синус 1.5 кГц уходит в mid, в low и high - в десятки раз меньше")
func midBandTakesMiddle() {
    let bands = split(sine(1500))

    #expect(peak(bands.mid) > 0.8)  // измерено 0.881
    #expect(peak(bands.mid) > 30 * peak(bands.low))  // измерено 0.881 против 0.0227
    #expect(peak(bands.mid) > 30 * peak(bands.high))  // измерено 0.881 против 0.0162
}

@Test("Верх: синус 8 кГц уходит в high, в mid - в пять раз меньше, в low - в тысячи")
func highBandTakesTreble() {
    let bands = split(sine(8000))

    #expect(peak(bands.high) > 0.8)  // измерено 0.899
    // mid - 4-й порядок, одна октава выше среза: вчетверо меньше, а не в сотни раз.
    #expect(peak(bands.high) > 4 * peak(bands.mid))  // измерено 0.899 против 0.184
    #expect(peak(bands.high) > 1000 * peak(bands.low))  // измерено 0.899 против 0.00002
}

@Test("Белый шум: не молчит ни одна из трёх полос")
func whiteNoiseFillsAllBands() {
    let bands = split(whiteNoise(count: Int(sampleRate)))

    #expect(peak(bands.low) > 0.1)  // измерено 0.66
    #expect(peak(bands.mid) > 0.1)  // измерено 0.42
    #expect(peak(bands.high) > 0.1)  // измерено 0.79
}

@Test("Разделитель не меняет длину сигнала и переживает пустой вход")
func splittingKeepsLength() {
    let samples = sine(1000, seconds: 0.25)
    let bands = split(samples)

    #expect(bands.low.count == samples.count)
    #expect(bands.mid.count == samples.count)
    #expect(bands.high.count == samples.count)

    let empty = split([])
    #expect(empty.low.isEmpty && empty.mid.isEmpty && empty.high.isEmpty)
}

@Test("Шва на склейке отрезков нет: фильтр отрезка прогревается предысторией")
func segmentsHaveNoFilterSpike() throws {
    let directory = try AudioFixture.makeDirectory()
    let url = directory.appending(path: "tone.wav")
    try writeTone(100, seconds: 2, to: url)
    let totalFrames = try PCMReader.frameCount(of: url)
    let framesPerColumn = max(1, totalFrames / WaveformData.columnCount)

    let head = try PCMReader.columnLevels(
        url: url, columns: 0..<1920, framesPerColumn: framesPerColumn, totalFrames: totalFrames)
    let tail = try PCMReader.columnLevels(
        url: url, columns: 1920..<3840, framesPerColumn: framesPerColumn, totalFrames: totalFrames)

    // У отрезка из середины файла первая колонка - обычный уровень полосы (0.0248), а не выброс.
    #expect(abs(tail.mid[0] - tail.mid[100]) < 0.001)
    // А на старте файла выброс есть: это настоящий переходный процесс с тишины, а не артефакт склейки.
    #expect(head.mid[0] > 2 * tail.mid[0])  // измерено 0.0522 против 0.0248
}

// MARK: - Анализатор

@Test("Анализатор: у синуса 100 Гц трек уезжает в полосу low, середина и верх почти пустые")
func analyzerPutsBassInLowBand() async throws {
    let data = try await analyzedTone(100)
    let steady = data.columns[WaveformData.columnCount / 2]

    #expect(data.columns.count == WaveformData.columnCount)
    #expect(steady.low > 0.9)  // измерено 0.996
    // Общий пик трёх полос: шлейф середины больше не раздувается собственным пиком до 0,37.
    #expect(steady.mid < 0.05)  // измерено 0.028 (2-й порядок ФВЧ на 600 Гц: 100/600 в четвёртой)
    #expect(steady.high < 0.001)  // измерено 0.00001
}

@Test("Анализатор: у синуса 8 кГц трек уезжает в полосу high, верх заметно громче середины")
func analyzerPutsTrebleInHighBand() async throws {
    let data = try await analyzedTone(8000)
    let steady = data.columns[WaveformData.columnCount / 2]

    #expect(steady.high > 0.9)  // измерено 0.997
    #expect(steady.high > 4 * steady.mid)  // измерено 0.997 против 0.204 (одна октава выше среза)
    // В первых колонках есть выброс фильтра (до 0.033), в середине трека низ пуст: 0.00003.
    #expect(steady.low < 0.001)
}

@Test("Кэш версии 1 больше не подходит: старый файл пересчитывается, а не читается как есть")
func oldCacheVersionIsRejected() async throws {
    let directory = try AudioFixture.makeDirectory()
    let url = directory.appending(path: "tone.wav")
    try writeTone(100, seconds: 1, to: url)
    let cache = WaveformCache(directory: directory.appending(path: "cache", directoryHint: .isDirectory))
    let data = try await WaveformAnalyzer(cache: cache).analyze(url: url)

    #expect(WaveformData.formatVersion == 3)
    #expect(try cache.load(for: url) == data)

    var stale = data.encoded()
    stale[4] = 1  // версия лежит сразу за сигнатурой "DJWF"
    #expect(throws: WaveformError.badCache) { try WaveformData.decoded(from: stale) }
}

@Test("Нечисловые пики не просачиваются в кэш: NaN, бесконечность и минус дают нули")
func garbagePeaksBecomeZeros() {
    let columns = WaveformAnalyzer.columns(
        BandLevels(low: [.nan, .infinity, -1, 0.5], mid: [.nan], high: []))

    #expect(columns.count == WaveformData.columnCount)
    #expect(columns[0].low == 0)  // NaN
    #expect(columns[1].low == 0)  // бесконечность
    #expect(columns[2].low == 0)  // отрицательное
    #expect(columns[3].low == 1)  // 0.5 - единственный положительный, он и есть пик полосы
    #expect(columns[WaveformData.columnCount - 1].low == 1)  // хвост добирается последним значением
    #expect(columns.allSatisfy { $0.low.isFinite && $0.mid == 0 && $0.high == 0 })
}

@Test("PBT: на любых пиках полос выходит ровно 3840 колонок со значениями в 0…1")
func columnsAreAlwaysNormalized() async {
    let band = Gen.float(in: -2...2).array(of: 0...WaveformData.columnCount)

    await propertyCheck(count: 50, input: band, band, band) { low, mid, high in
        let columns = WaveformAnalyzer.columns(BandLevels(low: low, mid: mid, high: high))
        #expect(columns.count == WaveformData.columnCount)
        #expect(columns.allSatisfy {
            $0.low >= 0 && $0.low <= 1 && $0.mid >= 0 && $0.mid <= 1 && $0.high >= 0 && $0.high <= 1
        })
    }
}
