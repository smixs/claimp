import AVFAudio
import Foundation
import SFBAudioEngine

@MainActor
public protocol PlayerEngineProtocol: AnyObject {
    var state: PlaybackState { get }
    var currentURL: URL? { get }
    /// 0…1; значение вне диапазона клампится.
    var volume: Float { get set }
    /// Тик 10 Гц, пока идёт воспроизведение. Поток создаётся один раз на весь срок жизни движка.
    var positions: AsyncStream<PlaybackPosition> { get }
    /// Трек доиграл до конца. Следующий выбирает App, не движок.
    var onEndOfTrack: (@MainActor () -> Void)? { get set }
    /// Сбой в вызове, который по контракту не бросает (`pause`, `stop`, `seek`, сеттер `volume`).
    /// Ошибка всегда с URL внутри: по ней App показывает алерт (SPEC §6.16).
    var onError: (@MainActor (PlayerEngineError) -> Void)? { get set }
    /// Готовит трек, не играет.
    func load(_ url: URL) throws
    func play() throws
    func pause()
    func stop()
    /// Перемотка по доле трека: значение вне 0…1 клампится, ошибки нет.
    func seek(fraction: Double)
}

/// Ошибка движка. URL всегда внутри: по нему App показывает алерт (SPEC §6.16).
public enum PlayerEngineError: Error, Equatable {
    case cannotOpen(URL)
    case notLoaded
}

/// Движок одного трека поверх `SFBAudioEngine.AudioPlayer`.
///
/// Целиком `@MainActor`. Делегат `AudioPlayer` приходит с чужого потока: колбэки принимает
/// `DelegateBox` и увозит на главный актор через `Task { @MainActor in ... }`. Сам движок
/// `Sendable` именно как `@MainActor`-тип, без `@unchecked Sendable`.
///
/// Дополнение к SPEC §5.2 (сигнатуры оттуда не тронуты): `onError` - канал ошибок для
/// вызовов, которые по контракту не бросают (`pause`, `stop`, `seek`, сеттер `volume`).
/// `false` от SFB нельзя проглотить (§6.16), а бросить из них нечем: §5.2 объявляет их
/// без `throws`, а `volume` - свойством. Колбэк видит App, потому что он в протоколе;
/// именованного поля для этого нет нарочно: его стирал бы следующий вызов транспорта.
@MainActor
public final class PlayerEngine: PlayerEngineProtocol {
    /// 10 Гц: чаще волне не нужно, курсор не должен прыгать.
    private static let tickInterval: TimeInterval = 0.1

    private let player = AudioPlayer()
    /// Шов делегата. Не `private`: тесты дёргают его напрямую, когда нет аудиоустройства.
    let delegateBox: DelegateBox
    private let positionStream: AsyncStream<PlaybackPosition>
    private let positionContinuation: AsyncStream<PlaybackPosition>.Continuation

    private var ticker: Timer?
    /// Доля, которую SFB не принял до старта рендера: снапшота позиции ещё нет.
    private var pendingSeekFraction: Double?
    /// Длительность из декодера. Нужна, пока SFB не отдал снапшот.
    private var loadedDuration: TimeInterval = 0
    private var storedVolume: Float = 1

    public private(set) var state: PlaybackState = .idle
    public private(set) var currentURL: URL?
    public var onEndOfTrack: (@MainActor () -> Void)?
    public var onError: (@MainActor (PlayerEngineError) -> Void)?

    public var volume: Float {
        get { storedVolume }
        set { apply(volume: newValue) }
    }

    public var positions: AsyncStream<PlaybackPosition> { positionStream }

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(
            of: PlaybackPosition.self,
            bufferingPolicy: .bufferingNewest(1))
        positionStream = stream
        positionContinuation = continuation

        let box = DelegateBox()
        delegateBox = box
        player.delegate = box
        // `onEvent` присваивается один раз здесь, до того как игрок начал звать делегата.
        box.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    // MARK: - Транспорт

    public func load(_ url: URL) throws {
        // load готовит трек, а не продолжает играть: гасим прежний декодер и очередь.
        player.stop()
        resetTransport()
        let decoder = try openDecoder(at: url)
        do {
            try player.enqueue(decoder)
        } catch {
            throw PlayerEngineError.cannotOpen(url)
        }
        currentURL = url
        loadedDuration = Self.duration(of: decoder)
        setState(.paused)
        publishPosition()
    }

    public func play() throws {
        guard let url = currentURL else { throw PlayerEngineError.notLoaded }
        guard state != .playing else { return }
        do {
            try player.play()
        } catch {
            throw PlayerEngineError.cannotOpen(url)
        }
        setState(.playing)
        publishPosition()
    }

    public func pause() {
        guard state == .playing else { return }
        guard player.pause() else {
            recordFailure()
            return
        }
        setState(.paused)
        publishPosition()
    }

    public func stop() {
        player.stop()
        resetTransport()
        publishPosition()
    }

    public func seek(fraction: Double) {
        guard currentURL != nil else {
            recordFailure()
            return
        }
        let clamped = Self.clamp(fraction)
        // SFB откажет, если рендер ещё не стартовал: запомним долю и применим в тике.
        pendingSeekFraction = player.seek(position: clamped) ? nil : clamped
        publishPosition(fraction: clamped)
    }

    // MARK: - Громкость

    private func apply(volume value: Float) {
        storedVolume = Self.clamp(value)
        do {
            try player.setVolume(storedVolume)
        } catch {
            recordFailure()
        }
    }

    // MARK: - Позиция

    /// Снимок позиции. С `fraction` - только что запрошенная перемотка: её отдаём сразу,
    /// иначе клик по волне до старта рендера не доедет до курсора.
    private func makePosition(fraction: Double? = nil) -> PlaybackPosition {
        let time = player.positionAndTime?.time
        let total = time?.total ?? loadedDuration
        guard let fraction else {
            return PlaybackPosition(current: time?.current ?? 0, total: total)
        }
        return PlaybackPosition(current: fraction * max(total, 0), total: total)
    }

    private func publishPosition(fraction: Double? = nil) {
        positionContinuation.yield(makePosition(fraction: fraction))
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            // Таймер живёт на главном run loop: `assumeIsolated` без хопа и без гонки.
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        applyPendingSeek()
        publishPosition()
    }

    /// До старта рендера снапшота позиции у SFB нет, и перемотка отбивается. Пробуем снова,
    /// как только снапшот появился; отказ после этого - настоящая ошибка, не молчим.
    private func applyPendingSeek() {
        guard let fraction = pendingSeekFraction, player.positionAndTime != nil else { return }
        pendingSeekFraction = nil
        if !player.seek(position: fraction) {
            recordFailure()
        }
    }

    // MARK: - Состояние

    private func setState(_ newState: PlaybackState) {
        state = newState
        if newState == .playing {
            startTicker()
        } else {
            stopTicker()
        }
    }

    /// Гасит транспорт и трек. `player.stop()` вызывает отдельно тот, кто начинает заново.
    private func resetTransport() {
        currentURL = nil
        loadedDuration = 0
        pendingSeekFraction = nil
        setState(.idle)
    }

    private func handle(_ event: DelegateBox.Event) {
        switch event {
        case .endOfAudio:
            finishPlayback()
            return
        case .didSeek:
            break
        case .playing:
            guard currentURL != nil else { return }
            setState(.playing)
        case .paused:
            guard currentURL != nil else { return }
            setState(.paused)
        case .stopped:
            // SFB сообщает `.stopped` и когда мы сами вытесняем декодер: пока трек загружен,
            // это не повод гасить состояние, которое ведёт движок.
            guard currentURL == nil else { return }
            setState(.idle)
            // Позиции нет - публиковать нечего. Публикация вернула бы курсор в 0 после конца
            // трека (§6.4): SFB шлёт `.stopped` из нашего же `player.stop()`.
            return
        }
        publishPosition()
    }

    /// Конец трека: SFB уже остановился сам. После колбэка трек больше не загружен - декодера
    /// нет, и `play()` без нового `load` честно бросит `notLoaded`.
    ///
    /// Гвард по `currentURL` даёт «ровно один раз»: повторный колбэк от SFB уже ничего не делает.
    private func finishPlayback() {
        guard let ended = currentURL else { return }
        player.stop()
        // SPEC §6.4: курсор остаётся в конце. Публикуем до `resetTransport()`: после него
        // длительность уже обнулена и наружу ушло бы 0/0.
        publishPosition(fraction: 1)
        // App выбирает следующий трек по `engine.currentURL`: держим его до конца колбэка,
        // иначе наружу уходит nil и App берёт первый трек списка вместо следующего.
        onEndOfTrack?()
        // В колбэке App мог загрузить следующий трек - тогда сбрасывать уже нечего.
        if currentURL == ended {
            resetTransport()
        }
    }

    /// Единая точка «не глотать»: любой `false` от SFB становится ошибкой с URL внутри
    /// и уезжает в `onError` - по ней App показывает алерт.
    private func recordFailure() {
        onError?(currentURL.map(PlayerEngineError.cannotOpen) ?? .notLoaded)
    }

    // MARK: - Декодер

    /// Открывает декодер синхронно: иначе `load` несуществующего файла молчал бы - SFB создаёт
    /// декодер в своём потоке и сообщает об ошибке только делегату.
    private func openDecoder(at url: URL) throws -> AudioDecoder {
        do {
            let decoder = try AudioDecoder(url: url)
            try decoder.open()
            return decoder
        } catch {
            throw PlayerEngineError.cannotOpen(url)
        }
    }

    /// Длительность из декодера: до старта рендера SFB снапшот не отдаёт, а `total` нужен
    /// уже на `load` - по нему волна считает долю.
    private static func duration(of decoder: AudioDecoder) -> TimeInterval {
        let rate = decoder.processingFormat.sampleRate
        guard rate > 0 else { return 0 }
        let frames = Double(decoder.length)
        return frames > 0 ? frames / rate : 0
    }

    /// Прижимает к 0…1. NaN - тоже 0: наружу NaN уезжать не должен.
    private static func clamp(_ value: Double) -> Double {
        guard !value.isNaN else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func clamp(_ value: Float) -> Float {
        Float(clamp(Double(value)))
    }
}

/// Мост между делегатом `AudioPlayer` (чужой поток) и главным актором.
///
/// Бокс нарочно не актор: методы `AudioPlayer.Delegate` приходят с потока SFB, а сам игрок
/// не `Sendable`. Бокс только переводит колбэки в события; переход на главный актор - забота
/// владельца (см. `PlayerEngine.init`).
final class DelegateBox: NSObject, AudioPlayer.Delegate {
    enum Event: Sendable, Equatable {
        case endOfAudio
        case playing
        case paused
        case stopped
        case didSeek
    }

    /// Присваивается один раз при сборке движка, до первого колбэка.
    var onEvent: (@Sendable (Event) -> Void)?

    func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        onEvent?(.endOfAudio)
    }

    func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        switch playbackState {
        case .playing:
            onEvent?(.playing)
        case .paused:
            onEvent?(.paused)
        case .stopped:
            onEvent?(.stopped)
        @unknown default:
            break
        }
    }

    func audioPlayer(_ audioPlayer: AudioPlayer,
                     didSeek decoder: any PCMDecoding,
                     toFrame frame: AVAudioFramePosition) {
        onEvent?(.didSeek)
    }
}
