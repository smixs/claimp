import Core
import Foundation
import Testing

@testable import Analysis

/// Живой анализ: тесты внутри идут по одному. Разбор часового трека берёт около гигабайта,
/// поэтому параллельно их не гоняем (лимит анализатора тут ни при чём - он общий на процесс,
/// а тесты создают свои экземпляры).
@Suite(.serialized)
struct TrackAnalyzerLiveTests {
    /// Корпус владельца в репозиторий не входит: путь задаётся `CLAIMP_CORPUS`, без него
    /// живые тесты пропускаются, а не врут.
    static let corpus: URL? = ProcessInfo.processInfo.environment["CLAIMP_CORPUS"].map { URL(fileURLWithPath: $0) }
    static let corpusAvailable = corpus.map { FileManager.default.fileExists(atPath: $0.path) } ?? false

    @Test("Клик-трек 128 BPM: анализатор попадает в темп")
    func syntheticClickTrackTempo() async throws {
        let directory = try ClickTrack.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try ClickTrack.write(bpm: 128, seconds: 20, to: directory.appending(path: "click.wav"))

        let analyzer = TrackAnalyzer()
        let outcome = try await analyzer.analyze(url: url)
        guard case .analyzed(let analysis) = outcome else {
            Issue.record("клик-трек 20 с не должен пропускаться: \(outcome)")
            return
        }
        let bpm = try #require(analysis.bpm, "темп клик-трека не определился")
        #expect(abs(bpm - 128) <= 2, "ожидали 128, получили \(bpm)")
        #expect(!analysis.beats.isEmpty)
    }

    @Test("Треки корпуса с тегом TBPM: анализ сходится с тегом", .enabled(if: corpusAvailable))
    func taggedCorpusTracksMatchTag() async throws {
        // Имена файлов не зашиты: берём из корпуса все треки, у которых есть тег темпа
        // (на 15.09.2026 их три из 155), и сверяем анализ с тегом.
        let scanner = LibraryScanner()
        let tagged = await scanner.scan(folder: try #require(Self.corpus)).filter { $0.bpm != nil }
        #expect(!tagged.isEmpty, "в корпусе не нашлось ни одного трека с тегом TBPM")

        let analyzer = TrackAnalyzer()
        for track in tagged {
            let expected = try #require(track.bpm)
            let outcome = try await analyzer.analyze(url: track.url)
            guard case .analyzed(let analysis) = outcome else {
                Issue.record("\(track.url.lastPathComponent): ожидали разбор, получили \(outcome)")
                continue
            }
            let bpm = try #require(analysis.bpm, "\(track.url.lastPathComponent): темп не определился")
            #expect(abs(bpm - expected) <= 2, "\(track.url.lastPathComponent): тег \(expected), анализ \(bpm)")
        }
    }

    @Test("Длинный микс пропускается с причиной, а не считается молча")
    func longMixIsSkippedWithReason() async throws {
        let directory = try ClickTrack.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try ClickTrack.write(bpm: 128, seconds: 20, to: directory.appending(path: "mix.wav"))

        // Порог опущен до 10 секунд: поведение то же, что у часового микса при пороге 15 минут,
        // но без файла на сотню мегабайт.
        let analyzer = TrackAnalyzer(maxDuration: 10)
        let outcome = try await analyzer.analyze(url: url)
        guard case .skippedTooLong(let duration) = outcome else {
            Issue.record("ожидали пропуск, получили \(outcome)")
            return
        }
        #expect(abs(duration - 20) <= 1)
    }

    @Test("Не аудио - явная ошибка с файлом и причиной, не пустой результат")
    func invalidInputFailsLoudly() async throws {
        let directory = try ClickTrack.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "not-audio.mp3")
        try Data("это не аудио".utf8).write(to: url)

        let analyzer = TrackAnalyzer()
        await #expect(throws: TrackAnalysisFailure.self) {
            try await analyzer.analyze(url: url)
        }
    }
}
