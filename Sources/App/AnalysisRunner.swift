import Analysis
import Core
import Foundation
import TagWriter

/// Что случилось с одним треком в фоновом разборе.
enum AnalysisEvent: Sendable {
    /// Готово. `inTag` = значения уже записаны в файл, то есть это теперь содержимое тега
    /// и оно главнее прежнего; из кэша приходит `false` - там тег поверх подставит сам трек.
    case ready(URL, bpm: Double?, key: String?, inTag: Bool)
    /// Микс длиннее порога: не считаем и говорим об этом вслух, а не оставляем пустоту молча.
    case skipped(URL, reason: String)
    /// Не сложилось. Посчитанные значения (если анализ до них дошёл) всё равно идут в ячейку -
    /// владелец видит число и отдельно счётчик ошибок.
    case failed(URL, reason: String, bpm: Double?, key: String?)
    /// Разбор оборвали (выход из приложения, новая папка): не ошибка.
    case cancelled(URL)
}

/// Фоновый разбор BPM и тональности для плейлиста: кэш в базе, очередь в акторе-анализаторе.
///
/// Здесь только порядок и доставка результатов в интерфейс; счётом и лимитом параллелизма
/// занимается `TrackAnalyzer`, приоритетом «тег важнее анализа» - сам `Track`.
@MainActor
final class AnalysisRunner {
    /// Одна задача на весь плейлист: новая папка отменяет предыдущий разбор.
    private var task: Task<Void, Never>?
    /// Анализатор пересобирается при смене настроек: диапазон темпа и порог длины живут в нём.
    private var analyzer: TrackAnalyzer
    private let store: PlayedStoring?
    /// Автоанализ выключен в настройках - очередь не заводится вовсе (решение владельца 19:49).
    private var autoAnalyze: Bool
    /// Треки в работе: при выключении автоанализа с них снимается плейсхолдер.
    private var queued: [URL] = []

    /// Треки, поставленные в очередь: в их ячейках BPM/Key показывается плейсхолдер.
    var onQueued: (([URL]) -> Void)?
    var onEvent: ((AnalysisEvent) -> Void)?

    init(store: PlayedStoring?, settings: AppSettings) {
        self.store = store
        analyzer = Self.makeAnalyzer(settings)
        autoAnalyze = settings.autoAnalyze
    }

    /// Настройки анализа (⌘,) применяются на лету: новые диапазон и порог действуют со
    /// следующего разбора, уже посчитанное не пересчитывается. Выключение гасит очередь.
    func apply(settings: AppSettings) {
        analyzer = Self.makeAnalyzer(settings)
        guard autoAnalyze != settings.autoAnalyze else { return }
        autoAnalyze = settings.autoAnalyze
        guard !autoAnalyze else { return }
        let stopped = queued
        cancel()
        // Плейсхолдеры в ячейках не остаются висеть: каждый трек закрывается отменой.
        for url in stopped { onEvent?(.cancelled(url)) }
    }

    /// Диапазон темпа и порог длины - из настроек, лимит параллелизма остаётся дефолтным
    /// (он про память машины, а не про вкус владельца).
    private static func makeAnalyzer(_ settings: AppSettings) -> TrackAnalyzer {
        TrackAnalyzer(
            range: TempoRange(lower: settings.tempoRange.minimumBPM),
            maxDuration: TimeInterval(settings.analysisMaxMinutes * 60))
    }

    /// Автостарт после скана: в очередь идут только треки без тега темпа или тональности,
    /// и только при включённой настройке (по умолчанию она выключена - решение владельца 16.09,
    /// считаем по правому клику).
    func start(tracks: [Track]) {
        guard autoAnalyze else {
            cancel()
            return
        }
        analyze(urls: tracks.filter { $0.bpm == nil || $0.key == nil }.map(\.url), force: false)
    }

    /// Разбор конкретных треков. Порядок очереди - порядок списка: слоты анализатора выдаются
    /// в порядке обращения. `force` - счёт по требованию владельца («Проанализировать треки»
    /// в контекстном меню): кэш не читается, посчитанное перезаписывает его.
    /// Новая очередь отменяет прежнюю: плейсхолдеры брошенных треков снимаются отменой.
    func analyze(urls: [URL], force: Bool) {
        let fresh = Set(urls)
        let stopped = queued.filter { !fresh.contains($0) }
        cancel()
        for url in stopped { onEvent?(.cancelled(url)) }
        guard !urls.isEmpty else { return }
        queued = urls
        onQueued?(urls)
        let analyzer = analyzer
        let store = store
        task = Task { [weak self] in
            await withTaskGroup(of: AnalysisEvent.self) { group in
                for url in urls {
                    group.addTask { await Self.analyze(url: url, force: force, analyzer: analyzer, store: store) }
                }
                for await event in group {
                    self?.onEvent?(event)
                }
            }
        }
    }

    /// Незавершённый разбор при выходе и при смене папки гасится вместе с сессией анализа.
    func cancel() {
        task?.cancel()
        task = nil
        queued = []
    }

    /// Один трек: сперва кэш по отпечатку файла, потом счёт. Работа идёт вне главного потока.
    /// `force` - пересчёт по требованию владельца: кэш не читается, свежий результат его заменяет.
    private nonisolated static func analyze(
        url: URL, force: Bool, analyzer: TrackAnalyzer, store: PlayedStoring?
    ) async -> AnalysisEvent {
        do {
            let stamp = try FileStamp.of(url: url)
            if !force, let cached = try store?.analysis(for: url, stamp: stamp) {
                return .ready(url, bpm: cached.bpm, key: cached.key, inTag: false)
            }
            switch try await analyzer.analyze(url: url) {
            case .skippedTooLong(let duration):
                let minutes = Int((duration / 60).rounded())
                return .skipped(
                    url, reason: "track is \(minutes) min, longer than the analysis limit")
            case .analyzed(let analysis):
                return persist(analysis, for: url, in: store)
            }
        } catch is CancellationError {
            return .cancelled(url)
        } catch {
            return .failed(url, reason: String(describing: error), bpm: nil, key: nil)
        }
    }

    /// Порядок обязателен (решение владельца 16.09 ~07:00): сначала тег в файле, потом свежий
    /// отпечаток, потом кэш. Запись меняет mtime, поэтому отпечаток берётся уже после неё -
    /// иначе следующий скан промахнётся мимо кэша и посчитает трек заново.
    /// Тег не записался - в кэш не пишем вовсе: источник правды тег, а не база.
    private nonisolated static func persist(
        _ analysis: TrackAnalysis, for url: URL, in store: PlayedStoring?
    ) -> AnalysisEvent {
        // В тег идёт нотная запись ("Am"): её читают Rekordbox, Serato и Traktor, а ID3v2 TKEY
        // по спеке не длиннее трёх символов. В интерфейсе и кэше остаётся код Camelot.
        let key = analysis.key?.camelot
        do {
            try TagWriter.write(bpm: analysis.bpm, key: analysis.key?.shortName, to: url)
            let stamp = try FileStamp.of(url: url)
            try store?.saveAnalysis(
                AnalysisRecord(bpm: analysis.bpm, key: key, analyzedAt: analysis.analyzedAt),
                for: url, stamp: stamp)
        } catch {
            return .failed(url, reason: String(describing: error), bpm: analysis.bpm, key: key)
        }
        return .ready(url, bpm: analysis.bpm, key: key, inTag: true)
    }
}
