import Foundation
import SFBAudioEngine
import Testing

@testable import Playback

/// Тесты тяжёлые: реальное воспроизведение и декодирование. Последовательно, чтобы не
/// выбивать чужие wall-clock проверки (в WaveformTests есть бюджет в 1 с) и не мерять
/// тики под нагрузкой от собственных соседей.
@MainActor
@Suite("Движок воспроизведения", .serialized)
struct PlayerEngineTests {
    // MARK: - Перемотка

    @Test("seek(fraction:) клампит долю в 0…1, а не отбрасывает её")
    func seekClamps() async throws {
        let engine = PlayerEngine()
        let url = PlaybackFixtures.url(named: PlaybackFixtures.toneName)
        try engine.load(url)
        #expect(engine.currentURL == url)

        let observer = PositionObserver(engine)
        defer { observer.stop() }

        engine.seek(fraction: -1)
        // Проверяем `current`, а не `fraction`: `fraction` сам клампит в 0…1 и простил бы
        // неклампленную перемотку. Без клампа здесь было бы -5 с на пятисекундном треке.
        #expect(await waitUntil { isClose(await observer.last()?.current, 0) })

        engine.seek(fraction: 2)
        #expect(await waitUntil { isClose(await observer.last()?.current, 5) })

        engine.seek(fraction: 0.5)
        #expect(await waitUntil { isClose(await observer.last()?.current, 2.5) })
    }

    @Test("Перемотка во время воспроизведения действительно доезжает до середины")
    func seekWhilePlayingMovesPosition() async throws {
        let engine = PlayerEngine()
        try engine.load(PlaybackFixtures.url(named: PlaybackFixtures.toneName))
        let observer = PositionObserver(engine)
        defer { observer.stop() }
        let log = ErrorLog()
        engine.onError = { log.errors.append($0) }

        try engine.play()
        #expect(await waitUntil { (await observer.last()?.current ?? 0) > 1 })

        engine.seek(fraction: 0.5)
        #expect(await waitUntil { (await observer.last()?.current ?? 0) > 2.5 })
        try await Task.sleep(for: .milliseconds(400))
        // 5-секундный трек: после перемотки в середину обязано быть около 2.5-3.6 с.
        // Если бы перемотка не сработала, здесь было бы около 1.4-1.9 с.
        let current = await observer.last()?.current ?? 0
        #expect(current > 2.3)
        #expect(current < 3.6)
        #expect(log.errors.isEmpty)
    }

    // MARK: - Загрузка

    @Test("load несуществующего файла бросает cannotOpen и не молчит")
    func loadMissingFileThrows() throws {
        let engine = PlayerEngine()
        let missing = URL(fileURLWithPath: "/tmp/claimp-missing-\(UUID().uuidString).wav")

        #expect(throws: PlayerEngineError.cannotOpen(missing)) {
            try engine.load(missing)
        }
        #expect(engine.state == .idle)
        #expect(engine.currentURL == nil)
    }

    @Test("load файла, который не аудио, бросает cannotOpen с этим URL")
    func loadNonAudioFileThrows() throws {
        let engine = PlayerEngine()
        let notAudio = URL(fileURLWithPath: #filePath)

        #expect(throws: PlayerEngineError.cannotOpen(notAudio)) {
            try engine.load(notAudio)
        }
        #expect(engine.state == .idle)
    }

    @Test("play() без load бросает notLoaded")
    func playWithoutLoadThrows() {
        let engine = PlayerEngine()
        #expect(throws: PlayerEngineError.notLoaded) {
            try engine.play()
        }
    }

    @Test("play() после stop() бросает notLoaded: декодера больше нет")
    func playAfterStopThrows() throws {
        let engine = PlayerEngine()
        try engine.load(PlaybackFixtures.url(named: PlaybackFixtures.toneName))

        engine.stop()
        #expect(engine.state == .idle)
        #expect(engine.currentURL == nil)
        #expect(throws: PlayerEngineError.notLoaded) {
            try engine.play()
        }
    }

    // MARK: - Громкость

    @Test("volume клампится в 0…1")
    func volumeClamps() {
        let engine = PlayerEngine()

        engine.volume = -0.5
        #expect(engine.volume == 0)

        engine.volume = 3
        #expect(engine.volume == 1)

        engine.volume = 0.4
        #expect(engine.volume == 0.4)

        engine.volume = .nan
        #expect(engine.volume == 0)
    }

    // MARK: - Позиция

    @Test("positions отдаёт позицию за 0.5 с после play() и fraction растёт")
    func positionsGrowWhilePlaying() async throws {
        let engine = PlayerEngine()
        try engine.load(PlaybackFixtures.url(named: PlaybackFixtures.toneName))
        let observer = PositionObserver(engine)
        defer { observer.stop() }

        try engine.play()
        #expect(await waitUntil(timeout: .milliseconds(500)) { await observer.last() != nil })

        let first = await observer.last()?.current ?? 0
        #expect(await waitUntil { (await observer.last()?.current ?? 0) > first + 0.05 })

        let last = await observer.last()
        #expect((last?.total ?? 0) > 0)
        #expect((last?.fraction ?? 0) > 0)
        #expect(engine.state == .playing)
    }

    @Test("positions не тикает на паузе")
    func positionsDoNotTickWhilePaused() async throws {
        let engine = PlayerEngine()
        try engine.load(PlaybackFixtures.url(named: PlaybackFixtures.toneName))
        let observer = PositionObserver(engine)
        defer { observer.stop() }

        try engine.play()
        #expect(await waitUntil { (await observer.last()?.current ?? 0) > 0.2 })

        engine.pause()
        #expect(engine.state == .paused)
        // Пока подписчик не дочитал поток, счётчик не меряем: в полёте может быть и тик,
        // и публикация самой паузы.
        try await Task.sleep(for: .milliseconds(200))
        let frozen = await observer.last()?.current ?? 0
        let ticksAtPause = await observer.count()
        try await Task.sleep(for: .milliseconds(400))

        // Таймер обязан быть погашен: за 400 мс он успел бы насыпать ~4 значения.
        // Одно запаздывающее значение после паузы допускаем - оно было в полёте.
        let after = await observer.count()
        #expect(after - ticksAtPause <= 1)
        #expect(abs((await observer.last()?.current ?? 0) - frozen) < 0.15)
    }

    // MARK: - Ошибки

    @Test("Сбой не-бросающего вызова доезжает до onError, а не копится в поле")
    func failureGoesToOnError() {
        // App держит протокол, а не класс: канал обязан быть в протоколе.
        let engine: any PlayerEngineProtocol = PlayerEngine()
        let log = ErrorLog()
        engine.onError = { log.errors.append($0) }

        engine.seek(fraction: 0.5)      // перематывать нечего: notLoaded
        engine.volume = 0.5             // следующий вызов ошибку не стирает
        engine.seek(fraction: 0.5)

        #expect(log.errors == [.notLoaded, .notLoaded])
    }

    @Test("Отказ SFB доезжает до onError с URL внутри")
    func sfbfailureGoesToOnError() async throws {
        let engine = PlayerEngine()
        let url = PlaybackFixtures.url(named: PlaybackFixtures.toneName)
        try engine.load(url)
        let log = ErrorLog()
        engine.onError = { log.errors.append($0) }

        // Двигаем состояние в `.playing` швом делегата: сам AVAudioEngine при этом не запущен.
        engine.delegateBox.audioPlayer(AudioPlayer(), playbackStateChanged: .playing)
        #expect(await waitUntil { engine.state == .playing })

        engine.pause()                  // SFB вернёт false: движок не запущен

        #expect(log.errors == [.cannotOpen(url)])
        engine.stop()
    }

    // MARK: - Конец трека

    @Test("onEndOfTrack приходит ровно один раз после конца короткого трека")
    func endOfTrackFiresOnce() async throws {
        let engine = PlayerEngine()
        try engine.load(PlaybackFixtures.url(named: PlaybackFixtures.toneName))
        let counter = Counter()
        engine.onEndOfTrack = { counter.value += 1 }
        let observer = PositionObserver(engine)
        defer { observer.stop() }

        try engine.play()
        #expect(await waitUntil(timeout: .seconds(8)) { counter.value == 1 })
        #expect(engine.state == .idle)
        #expect(engine.currentURL == nil)

        try await Task.sleep(for: .milliseconds(300))
        #expect(counter.value == 1)
        // SPEC §6.4: на последнем треке курсор остаётся в конце, а не прыгает в 0/0.
        // Пауза перед проверкой даёт позднему `.stopped` от SFB шанс испортить курсор.
        #expect(isClose(await observer.last()?.fraction, 1))
        #expect((await observer.last()?.total ?? 0) > 0)
    }

    @Test("Конец трека оставляет курсор в конце (шов DelegateBox)")
    func endOfTrackLeavesCursorAtEnd() async throws {
        let engine = PlayerEngine()
        try engine.load(PlaybackFixtures.url(named: PlaybackFixtures.toneName))
        let observer = PositionObserver(engine)
        defer { observer.stop() }
        #expect(await waitUntil { (await observer.last()?.total ?? 0) > 0 })

        engine.delegateBox.audioPlayerEndOfAudio(AudioPlayer())

        #expect(await waitUntil { isClose(await observer.last()?.fraction, 1) })
        let last = await observer.last()
        #expect((last?.total ?? 0) > 0)
        #expect(isClose(last?.current, last?.total ?? 0))
    }

    @Test("Повторный колбэк конца трека не срабатывает дважды (шов DelegateBox)")
    func endOfTrackIsIdempotentOnRepeatedCallback() async throws {
        let engine = PlayerEngine()
        try engine.load(PlaybackFixtures.url(named: PlaybackFixtures.toneName))
        let counter = Counter()
        engine.onEndOfTrack = { counter.value += 1 }

        let player = AudioPlayer()
        engine.delegateBox.audioPlayerEndOfAudio(player)
        #expect(await waitUntil { counter.value == 1 })

        engine.delegateBox.audioPlayerEndOfAudio(player)
        engine.delegateBox.audioPlayerEndOfAudio(player)
        try await Task.sleep(for: .milliseconds(100))
        #expect(counter.value == 1)
        #expect(engine.state == .idle)
        #expect(engine.currentURL == nil)
    }

    @Test("Колбэк конца трека без загруженного трека ничего не делает")
    func endOfTrackWithoutTrackIsIgnored() async throws {
        let engine = PlayerEngine()
        let counter = Counter()
        engine.onEndOfTrack = { counter.value += 1 }

        engine.delegateBox.audioPlayerEndOfAudio(AudioPlayer())
        try await Task.sleep(for: .milliseconds(100))
        #expect(counter.value == 0)
        #expect(engine.state == .idle)
    }

    @Test("Во время onEndOfTrack движок ещё помнит, какой трек кончился")
    func endOfTrackKeepsCurrentURLForCallback() async throws {
        let engine = PlayerEngine()
        let url = PlaybackFixtures.url(named: PlaybackFixtures.toneName)
        try engine.load(url)
        let seen = URLBox()
        engine.onEndOfTrack = { seen.value = engine.currentURL }

        engine.delegateBox.audioPlayerEndOfAudio(AudioPlayer())

        // App выбирает следующий трек только по `engine.currentURL`: без него он берёт первый.
        #expect(await waitUntil { seen.value != nil })
        #expect(seen.value == url)
        #expect(engine.currentURL == nil)   // а после колбэка трек уже не загружен
    }

    @Test("Загрузка следующего трека внутри onEndOfTrack не затирается")
    func endOfTrackDoesNotWipeTrackLoadedInCallback() async throws {
        let engine = PlayerEngine()
        let first = PlaybackFixtures.url(named: PlaybackFixtures.toneName)
        let second = PlaybackFixtures.url(named: "tone.aiff")
        try engine.load(first)
        let log = ErrorLog()
        engine.onEndOfTrack = { [weak engine] in
            guard let engine else { return }
            do {
                try engine.load(second)
            } catch {
                log.errors.append(.cannotOpen(second))
            }
        }

        engine.delegateBox.audioPlayerEndOfAudio(AudioPlayer())

        #expect(await waitUntil { engine.currentURL == second })
        #expect(log.errors.isEmpty)
        #expect(engine.state == .paused)
    }
}
