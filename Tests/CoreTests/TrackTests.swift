import Foundation
import Testing

@testable import Core

private func makeTrack(
    _ name: String,
    title: String? = nil,
    artist: String? = nil,
    album: String = "",
    year: Int? = nil,
    duration: TimeInterval = 120,
    bitrate: Int? = nil,
    sampleRate: Int? = nil,
    format: String = "MP3",
    artwork: Data? = nil,
    isPlayed: Bool = false
) -> Track {
    Track(
        url: URL(fileURLWithPath: "/tmp/\(name).mp3"),
        title: title ?? name,
        artist: artist ?? "",
        album: album,
        year: year,
        duration: duration,
        bitrate: bitrate,
        sampleRate: sampleRate,
        format: format,
        artwork: artwork,
        isPlayed: isPlayed
    )
}

@Test("Пустой год в теге показывается пустой ячейкой")
func emptyYearRendersEmpty() {
    #expect(makeTrack("a").displayYear == "")
}

@Test("Год из тега показывается как есть")
func yearRendersAsIs() {
    #expect(makeTrack("a", year: 1997).displayYear == "1997")
}

@Test("Длительность форматируется m:ss и h:mm:ss")
func displayDurationFormats() {
    #expect(makeTrack("a", duration: 0).displayDuration == "0:00")
    #expect(makeTrack("a", duration: 61).displayDuration == "1:01")
    #expect(makeTrack("a", duration: 1927).displayDuration == "32:07")
    #expect(makeTrack("a", duration: 4365).displayDuration == "1:12:45")
    #expect(makeTrack("a", duration: 3600).displayDuration == "1:00:00")
}

@Test("Подпись шапки собирает формат, частоту, битрейт и год")
func headerSubtitleFull() {
    let track = makeTrack("a", year: 2014, duration: 1927, bitrate: 320, sampleRate: 44100)
    #expect(track.headerSubtitle == "MP3 · 44 kHz · 320 kbps · 2014")
}

@Test("Подпись шапки пропускает пустые части")
func headerSubtitleSkipsEmpty() {
    #expect(makeTrack("a", format: "FLAC").headerSubtitle == "FLAC")
    #expect(makeTrack("a", format: "").headerSubtitle == "")
}
