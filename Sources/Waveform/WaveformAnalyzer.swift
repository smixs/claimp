import Accelerate
import Foundation

public protocol WaveformAnalyzing: Sendable {
    /// Считает волну (или отдаёт из кэша). Тяжёлая работа вне главного потока, память константная.
    func analyze(url: URL) async throws -> WaveformData
}

public struct WaveformAnalyzer: WaveformAnalyzing, Sendable {
    /// Больше восьми потоков декодера не даёт выигрыша, а память растёт линейно.
    static let maxWorkers = 8
    /// Короче примерно тридцати секунд отрезок дробить нет смысла - накладные расходы съедают выигрыш.
    static let minFramesPerWorker = 1_500_000

    private let cache: WaveformCache

    public init(cache: WaveformCache = .default) {
        self.cache = cache
    }

    public func analyze(url: URL) async throws -> WaveformData {
        guard !Task.isCancelled else { throw WaveformError.cancelled }
        if let cached = try cache.load(for: url) { return cached }
        let data = try await detachedAnalysis(of: url)
        try cache.store(data, for: url)
        return data
    }

    /// Считаем вне вызывающего потока; наружу уезжает только значение `WaveformData`.
    private func detachedAnalysis(of url: URL) async throws -> WaveformData {
        let work = Task.detached(priority: .utility) { try await Self.bandLevels(of: url) }
        // `Task.detached` не наследует отмену (SPEC §5.4): если родитель успел отмениться между
        // входным гвардом и постановкой обработчика, `withTaskCancellationHandler` уже не поможет -
        // гасим работу руками и уходим тем же `cancelled`, а не добегаем до конца анализа.
        guard !Task.isCancelled else {
            work.cancel()
            throw WaveformError.cancelled
        }
        do {
            let levels = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            return WaveformData(columns: Self.columns(levels))
        } catch is CancellationError {
            throw WaveformError.cancelled
        }
    }

    /// Уровни (RMS) трёх полос по всем колонкам: трек режется на отрезки по границам колонок,
    /// каждый отрезок читается и фильтруется параллельно.
    private static func bandLevels(of url: URL) async throws -> BandLevels {
        let totalFrames = try PCMReader.frameCount(of: url)
        let framesPerColumn = max(1, totalFrames / WaveformData.columnCount)
        var levels = BandLevels(
            low: [Float](repeating: 0, count: WaveformData.columnCount),
            mid: [Float](repeating: 0, count: WaveformData.columnCount),
            high: [Float](repeating: 0, count: WaveformData.columnCount))
        try await withThrowingTaskGroup(of: (Int, BandLevels).self) { group in
            for columns in segments(totalFrames: totalFrames) {
                group.addTask {
                    (columns.lowerBound, try PCMReader.columnLevels(
                        url: url, columns: columns,
                        framesPerColumn: framesPerColumn, totalFrames: totalFrames))
                }
            }
            for try await (start, part) in group {
                for index in 0..<part.count {
                    levels.low[start + index] = part.low[index]
                    levels.mid[start + index] = part.mid[index]
                    levels.high[start + index] = part.high[index]
                }
            }
        }
        // Файл короче 3840 фреймов: лишние колонки отрезаем, хвост добьётся при сборке колонок.
        let covered = min(WaveformData.columnCount, max(1, totalFrames / framesPerColumn))
        return levels.prefix(covered)
    }

    /// Колонки из сырых RMS полос: все три полосы нормируются **одним общим пиком**, поэтому
    /// межполосные отношения - то есть цвет столбика - не врут (каждая полоса по своему пику
    /// раздувала бы тихую полосу до 1,0). Короткий вход добирается последним значением до ровно
    /// `WaveformData.columnCount` колонок.
    static func columns(_ levels: BandLevels) -> [WaveformData.Column] {
        let low = sanitized(levels.low)
        let mid = sanitized(levels.mid)
        let high = sanitized(levels.high)
        let peak = max(low.max() ?? 0, max(mid.max() ?? 0, high.max() ?? 0))
        let normalizedLow = scaled(low, by: peak)
        let normalizedMid = scaled(mid, by: peak)
        let normalizedHigh = scaled(high, by: peak)
        return (0..<WaveformData.columnCount).map { index in
            WaveformData.Column(
                low: value(normalizedLow, at: index),
                mid: value(normalizedMid, at: index),
                high: value(normalizedHigh, at: index))
        }
    }

    /// Значение полосы для колонки: если посчитанных колонок меньше, берётся последнее значение -
    /// короткий файл рисуется полосой, а не обрывом в пустоту. Пустая полоса даёт нули.
    private static func value(_ band: [Float], at index: Int) -> Float {
        guard let last = band.last else { return 0 }
        return index < band.count ? band[index] : last
    }

    /// Диапазоны колонок для параллельных читателей; границы отрезков совпадают с границами колонок.
    static func segments(totalFrames: Int) -> [Range<Int>] {
        let byLength = max(1, totalFrames / minFramesPerWorker)
        let workers = min(maxWorkers, ProcessInfo.processInfo.activeProcessorCount, byLength)
        let columnsPerWorker = (WaveformData.columnCount + workers - 1) / workers
        return stride(from: 0, to: WaveformData.columnCount, by: columnsPerWorker).map {
            $0..<min(WaveformData.columnCount, $0 + columnsPerWorker)
        }
    }

    /// Нечисловые и отрицательные значения - нули: ни NaN, ни выход за 0…1 в кэш не просочится.
    private static func sanitized(_ values: [Float]) -> [Float] {
        values.map { $0.isFinite ? max($0, 0) : 0 }
    }

    /// Деление полосы на общий пик трёх полос. Нулевой пик (тишина) оставляет ровно нули,
    /// поэтому деления на ноль нет.
    private static func scaled(_ values: [Float], by peak: Float) -> [Float] {
        guard peak > 0 else { return values }
        var divisor = peak
        var result = values
        vDSP_vsdiv(values, 1, &divisor, &result, 1, vDSP_Length(values.count))
        return result
    }
}
