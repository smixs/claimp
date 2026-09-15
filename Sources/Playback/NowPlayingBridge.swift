// Parts adapted from bocan/bocan-music (Apache-2.0)
import AppKit
import Foundation
import MediaPlayer

/// Мост в системный «Пункт управления»: медиаклавиши F7/F8/F9 и `nowPlayingInfo`.
///
/// Целиком `@MainActor`: `MPRemoteCommandCenter.shared()` - main-thread singleton
/// (`bocan-music/Modules/Playback/Sources/Playback/NowPlaying/RemoteCommands.swift:9-10`).
///
/// Что взято из `bocan-music` и что изменено:
/// - структура регистрации команд с замыканиями-хендлерами и идемпотентный `register()` -
///   как в `RemoteCommands.swift:11-45`, упрощено до пяти команд;
/// - заполнение `nowPlayingInfo` - как в `NowPlayingCentre.swift:24-61`.
///
/// Отличия от клона, обе сознательные:
/// - токен против гонки обложки не нужен: в нашем контракте обложка приходит готовым `Data` и
///   декодируется лениво внутри `requestHandler`, который привязан к актуальному словарю, -
///   «поздней» обложке из прошлого трека неоткуда взяться;
/// - тикера позиции здесь нет: время приходит параметром `update(elapsed:)` в момент события
///   транспорта. Переписывать `elapsed` по таймеру - джиттер: таймстемп словаря система
///   интерполирует сама.
@MainActor
public final class NowPlayingBridge {
    /// Медиаклавиша play.
    public var onPlay: (@MainActor () -> Void)?
    /// Медиаклавиша pause.
    public var onPause: (@MainActor () -> Void)?
    /// Медиаклавиша play/pause (F8).
    public var onToggle: (@MainActor () -> Void)?
    /// Следующий трек (F9).
    public var onNext: (@MainActor () -> Void)?
    /// Предыдущий трек (F7).
    public var onPrevious: (@MainActor () -> Void)?

    /// Идемпотентность `register()`: второй вызов ничего не регистрирует.
    private(set) var isRegistered = false
    /// Токены от `MPRemoteCommandCenter`. Держим ссылки и считаем их в тестах.
    private(set) var commandTargets: [Any] = []

    public init() {}

    // MARK: - Регистрация команд

    /// Пять команд медиаклавиш. Идемпотентно: повторный вызов - no-op.
    public func register() {
        guard !isRegistered else { return }
        isRegistered = true
        let center = MPRemoteCommandCenter.shared()
        for command in Command.allCases {
            let remote = command.remote(center)
            remote.isEnabled = true
            commandTargets.append(remote.addTarget { [weak self] _ in
                guard let self else { return .commandFailed }
                Task { @MainActor in command.invoke(self) }
                return .success
            })
        }
    }

    /// Пять команд медиаклавиш. Не `private`: тесты проверяют их привязку к системным командам.
    enum Command: CaseIterable {
        case play
        case pause
        case toggle
        case next
        case previous

        @MainActor
        func remote(_ center: MPRemoteCommandCenter) -> MPRemoteCommand {
            switch self {
            case .play: center.playCommand
            case .pause: center.pauseCommand
            case .toggle: center.togglePlayPauseCommand
            case .next: center.nextTrackCommand
            case .previous: center.previousTrackCommand
            }
        }

        @MainActor
        func invoke(_ bridge: NowPlayingBridge) {
            switch self {
            case .play: bridge.onPlay?()
            case .pause: bridge.onPause?()
            case .toggle: bridge.onToggle?()
            case .next: bridge.onNext?()
            case .previous: bridge.onPrevious?()
            }
        }
    }

    // MARK: - Информация о треке

    /// Показывает трек в «Пункте управления».
    ///
    /// Вызывается по событиям транспорта (старт, пауза, перемотка, смена трека), не по таймеру.
    /// `rate` - 1 при воспроизведении, 0 на паузе: система определяет по нему состояние.
    public func update(title: String, artist: String, album: String,
                       duration: TimeInterval, elapsed: TimeInterval,
                       rate: Double, artwork: Data?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork {
            info[MPMediaItemPropertyArtwork] = Self.makeArtwork(artwork)
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = rate > 0 ? .playing : .paused
    }

    /// Убирает текущий трек из системы.
    public func clear() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    /// Обложка декодируется в момент запроса, а не в `update`: DJ щёлкает треки быстро,
    /// декодировать JPEG в главном потоке на каждый щелчок нельзя. Хендлер не возвращает nil
    /// никогда - система такой ответ не переживает (пустая картинка вместо отсутствия).
    ///
    /// `nonisolated` и явный `@Sendable` обязательны: система зовёт хендлер со своей очереди,
    /// и замыкание, унаследовавшее главный актор, упало бы на проверке изоляции.
    private nonisolated static func makeArtwork(_ data: Data) -> MPMediaItemArtwork {
        let handler: @Sendable (CGSize) -> NSImage = { _ in
            NSImage(data: data) ?? placeholderImage()
        }
        return MPMediaItemArtwork(boundsSize: CGSize(width: 600, height: 600), requestHandler: handler)
    }

    /// Пустая картинка 1×1, но с настоящей битмапой: у `NSImage(size:)` нет представления,
    /// и система не может его сериализовать (ругается в лог `CGImageDestinationFinalize`).
    private nonisolated static func placeholderImage() -> NSImage {
        let size = NSSize(width: 1, height: 1)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else {
            return NSImage(size: size)
        }
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
