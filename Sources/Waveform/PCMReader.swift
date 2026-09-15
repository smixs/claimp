import AVFoundation
import Accelerate
import Foundation

/// Потоковое чтение PCM: трек читается кусками по 10 секунд, целиком в память не попадает
/// (час стерео - это 1.27 ГБ, так делать нельзя).
enum PCMReader {
    /// Сколько секунд аудио читаем за один `read` (как у aural-player).
    static let chunkSeconds: Double = 10
    /// Сколько секунд прогоняем через фильтры до начала отрезка: без прогрева первый столбик
    /// каждого отрезка ловил бы переходный процесс фильтра и вспыхивал бы на цветной волне.
    static let warmUpSeconds: Double = 0.5

    static func open(_ url: URL) throws -> AVAudioFile {
        guard let file = try? AVAudioFile(forReading: url) else { throw WaveformError.cannotOpen(url) }
        return file
    }

    static func frameCount(of url: URL) throws -> Int {
        Int(try open(url).length)
    }

    /// Уровни (RMS) трёх полос по колонкам из диапазона `columns`: файл открывается заново
    /// и читается только на своём отрезке, поэтому отрезки считаются параллельно.
    static func columnLevels(
        url: URL,
        columns: Range<Int>,
        framesPerColumn: Int,
        totalFrames: Int
    ) throws -> BandLevels {
        try BandReader(url: url).levels(
            columns: columns, framesPerColumn: framesPerColumn, totalFrames: totalFrames)
    }
}

/// Читатель одного отрезка: открытый файл, буфер чтения, по фильтру на канал и память под полосы.
/// Живёт внутри одной задачи-читателя, поэтому указатели и состояние фильтров наружу не уезжают.
private final class BandReader {
    private let url: URL
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let buffer: AVAudioPCMBuffer
    private let capacity: Int
    private let channels: Int
    private let splitters: [BandSplitter]
    /// Отфильтрованные полосы по каналам: `low | mid | high` подряд, по `capacity` значений на полосу.
    private var filtered: [[Float]]

    init(url: URL) throws {
        let file = try PCMReader.open(url)
        self.url = url
        let format = file.processingFormat
        let capacity = Int(format.sampleRate * PCMReader.chunkSeconds)
        guard capacity > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity))
        else { throw WaveformError.cannotOpen(url) }
        // В анализ идут максимум два канала: в колонку пишем максимум RMS по ним,
        // микс в моно усреднением съел бы противофазу.
        let channels = min(Int(format.channelCount), 2)
        self.file = file
        self.format = format
        self.capacity = capacity
        self.buffer = buffer
        self.channels = channels
        splitters = (0..<channels).map { _ in BandSplitter(sampleRate: format.sampleRate) }
        filtered = (0..<channels).map { _ in [Float](repeating: 0, count: 3 * capacity) }
    }

    /// Уровни полос по колонкам отрезка. Файл читается со своего первого кадра, но фильтры
    /// прогреваются на предыстории: иначе на склейке отрезков был бы выброс.
    func levels(columns: Range<Int>, framesPerColumn: Int, totalFrames: Int) throws -> BandLevels {
        let firstFrame = columns.lowerBound * framesPerColumn
        let lastFrame = min(totalFrames, columns.upperBound * framesPerColumn)
        try warmUp(until: firstFrame)
        // Колонка почти всегда разрезана границей куска чтения, поэтому копим сумму квадратов
        // и число кадров, а RMS считаем один раз в конце: «RMS куска, потом максимум» - неверно.
        var sums = [Float](repeating: 0, count: channels * 3 * columns.count)
        var counts = [Int](repeating: 0, count: channels * columns.count)
        file.framePosition = AVAudioFramePosition(firstFrame)
        var frame = firstFrame
        while frame < lastFrame {
            try Task.checkCancellation()
            // Короткое чтение - это битый хвост, а не тишина: ошибка с URL и позицией
            // вместо нулевых колонок (§6.16 «Молча глотать нельзя ничего»).
            try read(frames: lastFrame - frame, at: frame)
            let read = Int(buffer.frameLength)
            guard let samples = buffer.floatChannelData else { throw WaveformError.cannotOpen(url) }
            filter(samples: samples, frames: read)
            accumulate(&sums, &counts, frames: read, firstFrame: frame,
                       columns: columns, framesPerColumn: framesPerColumn)
            frame += read
        }
        return Self.rms(sums, counts, channels: channels, columnCount: columns.count)
    }

    /// Прогоняет через фильтры предысторию отрезка (не длиннее `warmUpSeconds` секунд),
    /// чтобы состояние фильтров к первому кадру было рабочим, а не нулевым.
    private func warmUp(until firstFrame: Int) throws {
        var frame = max(0, firstFrame - Int(PCMReader.warmUpSeconds * format.sampleRate))
        guard frame < firstFrame else { return }
        file.framePosition = AVAudioFramePosition(frame)
        while frame < firstFrame {
            try Task.checkCancellation()
            try read(frames: firstFrame - frame, at: frame)
            let read = Int(buffer.frameLength)
            guard let samples = buffer.floatChannelData else { throw WaveformError.cannotOpen(url) }
            filter(samples: samples, frames: read)
            frame += read
        }
    }

    /// Чтение одного куска с позиции: короткое или битое чтение - cannotRead с URL
    /// и позицией, а не молчаливый выход (fail fast из master).
    private func read(frames: Int, at frame: Int) throws {
        do {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(capacity, frames)))
        } catch let cancelled as CancellationError {
            throw cancelled
        } catch {
            throw WaveformError.cannotRead(url, frame)
        }
        guard Int(buffer.frameLength) > 0 else { throw WaveformError.cannotRead(url, frame) }
    }

    /// Прогоняет прочитанный кусок через три фильтра каждого канала: результат остаётся в `filtered`.
    private func filter(samples: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {
        for channel in 0..<channels {
            filtered[channel].withUnsafeMutableBufferPointer { bands in
                let base = bands.baseAddress!
                splitters[channel].split(
                    samples[channel], low: base, mid: base + capacity, high: base + 2 * capacity,
                    count: frames)
            }
        }
    }

    /// Раскладывает отфильтрованный кусок по колонкам, копя сумму квадратов и число кадров полосы.
    private func accumulate(
        _ sums: inout [Float],
        _ counts: inout [Int],
        frames: Int,
        firstFrame: Int,
        columns: Range<Int>,
        framesPerColumn: Int
    ) {
        let columnCount = columns.count
        for channel in 0..<channels {
            let sumBase = channel * 3 * columnCount
            let countBase = channel * columnCount
            filtered[channel].withUnsafeBufferPointer { bands in
                let base = bands.baseAddress!
                var offset = 0
                while offset < frames {
                    let column = min(columns.upperBound - 1, (firstFrame + offset) / framesPerColumn)
                    let untilNextColumn = (column + 1) * framesPerColumn - (firstFrame + offset)
                    let take = min(frames - offset, max(1, untilNextColumn))
                    let index = column - columns.lowerBound
                    let length = vDSP_Length(take)
                    vDSP_svesq(base + offset, 1, &sums[sumBase + index], length)
                    vDSP_svesq(base + capacity + offset, 1, &sums[sumBase + columnCount + index], length)
                    vDSP_svesq(
                        base + 2 * capacity + offset, 1, &sums[sumBase + 2 * columnCount + index], length)
                    counts[countBase + index] += take
                    offset += take
                }
            }
        }
    }

    /// RMS полос по колонкам: на колонку - максимум по каналам (как и было у пиков), тишина
    /// без кадров остаётся ровно нулями, деления на ноль нет.
    private static func rms(
        _ sums: [Float], _ counts: [Int], channels: Int, columnCount: Int
    ) -> BandLevels {
        var low = [Float](repeating: 0, count: columnCount)
        var mid = [Float](repeating: 0, count: columnCount)
        var high = [Float](repeating: 0, count: columnCount)
        for channel in 0..<channels {
            let sumBase = channel * 3 * columnCount
            let countBase = channel * columnCount
            for column in 0..<columnCount {
                let frames = counts[countBase + column]
                guard frames > 0 else { continue }
                let divisor = Float(frames)
                low[column] = max(low[column], (sums[sumBase + column] / divisor).squareRoot())
                mid[column] = max(mid[column], (sums[sumBase + columnCount + column] / divisor).squareRoot())
                high[column] = max(
                    high[column], (sums[sumBase + 2 * columnCount + column] / divisor).squareRoot())
            }
        }
        return BandLevels(low: low, mid: mid, high: high)
    }
}
