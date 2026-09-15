import Foundation
import MediaPlayer
import Testing

@testable import Playback

@MainActor
@Suite("NowPlayingBridge")
struct NowPlayingBridgeTests {
    @Test("register() регистрирует хендлеры один раз, clear() обнуляет nowPlayingInfo")
    func registerIsIdempotentAndClearResets() {
        let bridge = NowPlayingBridge()
        #expect(!bridge.isRegistered)

        bridge.register()
        #expect(bridge.isRegistered)
        #expect(bridge.commandTargets.count == 5)
        #expect(MPRemoteCommandCenter.shared().playCommand.isEnabled)
        #expect(MPRemoteCommandCenter.shared().pauseCommand.isEnabled)
        #expect(MPRemoteCommandCenter.shared().togglePlayPauseCommand.isEnabled)
        #expect(MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
        #expect(MPRemoteCommandCenter.shared().previousTrackCommand.isEnabled)

        bridge.register()
        #expect(bridge.commandTargets.count == 5)

        bridge.update(title: "Track", artist: "Artist", album: "Album",
                      duration: 120, elapsed: 12, rate: 1, artwork: nil)
        let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        #expect(info?[MPMediaItemPropertyTitle] as? String == "Track")
        #expect(info?[MPMediaItemPropertyArtist] as? String == "Artist")
        #expect(info?[MPMediaItemPropertyAlbumTitle] as? String == "Album")
        #expect(info?[MPMediaItemPropertyPlaybackDuration] as? TimeInterval == 120)
        #expect(info?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? TimeInterval == 12)
        #expect(info?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)

        bridge.clear()
        #expect(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil)
    }

    @Test("Пять команд моста привязаны каждая к своей системной команде")
    func commandsMapToSystemCommands() {
        let bridge = NowPlayingBridge()
        let center = MPRemoteCommandCenter.shared()
        let expected: [(NowPlayingBridge.Command, MPRemoteCommand)] = [
            (.play, center.playCommand),
            (.pause, center.pauseCommand),
            (.toggle, center.togglePlayPauseCommand),
            (.next, center.nextTrackCommand),
            (.previous, center.previousTrackCommand),
        ]
        #expect(expected.count == 5)
        for (command, remote) in expected {
            #expect(command.remote(center) === remote)
        }
        #expect(bridge.commandTargets.isEmpty)
    }

    @Test("Хендлер обложки не возвращает nil даже на мусорные данные")
    func artworkHandlerNeverReturnsNil() {
        let bridge = NowPlayingBridge()
        bridge.update(title: "Track", artist: "Artist", album: "",
                      duration: 10, elapsed: 0, rate: 0,
                      artwork: Data([0x00, 0x01, 0x02, 0x03]))

        let artwork = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtwork]
            as? MPMediaItemArtwork
        #expect(artwork != nil)
        #expect(artwork?.image(at: CGSize(width: 300, height: 300)) != nil)

        bridge.clear()
    }
}
