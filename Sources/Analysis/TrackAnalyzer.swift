import AVFoundation
import Foundation
import MusicUnderstanding

/// Анализ не сложился: причина и файл, на котором она случилась. Пустого результата вместо
/// ошибки не бывает - её показывают счётчиком в статусной строке и пишут в stderr.
public struct TrackAnalysisFailure: Error, Sendable, CustomStringConvertible {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }

    public var description: String {
        "analysis failed: \(url.lastPathComponent) (\(reason))"
    }
}

/// Очередь анализа BPM и тональности на системном MusicUnderstanding.
///
/// Почему актор с явным счётчиком, а не просто задачи: на часовом файле один разбор
/// `rhythm + key` берёт 1,06 ГБ (research/06 §2.2), поэтому одновременно считаются не больше
/// двух треков. Слоты выдаются в порядке обращения, так что фоновый разбор идёт сверху списка.
public actor TrackAnalyzer {
    /// Треки длиннее (миксы) не анализируются: час аудио - это полторы минуты счёта
    /// и гигабайт памяти. Решение владельца 15.09 19:00.
    public static let maxDuration: TimeInterval = 15 * 60
    /// Одновременно считаются два трека, не больше.
    public static let concurrencyLimit = 2

    private let range: TempoRange
    private let limit: Int
    private let maxDuration: TimeInterval
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Порог длины вынесен в параметр только ради теста на пропуск: в приложении он всегда
    /// дефолтный.
    public init(
        range: TempoRange = .default,
        limit: Int = TrackAnalyzer.concurrencyLimit,
        maxDuration: TimeInterval = TrackAnalyzer.maxDuration
    ) {
        precondition(limit > 0, "concurrency limit must be greater than zero")
        precondition(maxDuration > 0, "duration limit must be greater than zero")
        self.range = range
        self.limit = limit
        self.maxDuration = maxDuration
    }

    /// Разбирает трек, дождавшись свободного слота. Отмена задачи гасит и сессию анализа.
    /// Ошибки фреймворка уходят наверх как `TrackAnalysisFailure` с файлом и причиной.
    public func analyze(url: URL) async throws -> AnalysisOutcome {
        await acquireSlot()
        defer { releaseSlot() }
        try Task.checkCancellation()
        do {
            return try await run(url: url)
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as TrackAnalysisFailure {
            throw failure
        } catch {
            throw TrackAnalysisFailure(url: url, reason: String(describing: error))
        }
    }

    private func run(url: URL) async throws -> AnalysisOutcome {
        let asset = AVURLAsset(url: url)
        let duration = try await CMTimeGetSeconds(asset.load(.duration))
        guard duration.isFinite, duration > 0 else {
            throw TrackAnalysisFailure(url: url, reason: "cannot read file duration")
        }
        guard duration <= maxDuration else {
            return .skippedTooLong(duration: duration)
        }
        let session = try await MusicUnderstandingSession(asset: asset)
        let result = try await withTaskCancellationHandler {
            try await session.analyze(for: [.rhythm, .key])
        } onCancel: {
            // Сессия - актор, отмену ей можно отправить только асинхронно; без этого
            // закрытое приложение досчитывало бы трек в фоне.
            Task { await session.cancel() }
        }
        try Task.checkCancellation()
        return .analyzed(TrackAnalysis(
            bpm: result.rhythm?.beatsPerMinute.flatMap { range.normalized(Double($0)) },
            key: try key(from: result.key, url: url),
            beats: result.rhythm?.beats.map(CMTimeGetSeconds) ?? [],
            analyzedAt: Date()))
    }

    /// Тональность трека - первый (на практике единственный) диапазон ответа.
    /// Незнакомое имя тоники - ошибка с именем, а не тихий nil: значит, список имён Apple
    /// изменился и свёртку надо чинить.
    private func key(from result: KeyResult?, url: URL) throws -> MusicalKey? {
        guard let signature = result?.ranges.first?.value else { return nil }
        guard let key = MusicalKey(
            appleTonicName: signature.tonic.rawValue, modeName: signature.mode.rawValue)
        else {
            throw TrackAnalysisFailure(
                url: url, reason: "unknown framework tonic: \(signature.tonic.rawValue)")
        }
        return key
    }

    // MARK: - Слоты

    private func acquireSlot() async {
        guard running >= limit else {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
        }
    }

    /// Слот не отпускается, а передаётся первому в очереди: `running` при этом не меняется.
    private func releaseSlot() {
        guard waiting.isEmpty else {
            waiting.removeFirst().resume()
            return
        }
        running -= 1
    }
}
