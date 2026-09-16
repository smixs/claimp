import Foundation
import PropertyBased
import Testing

@testable import Core

/// Песочница в temp: каталог на прогон, файлы кладутся по месту. Так же устроены
/// тесты сканера и кэша анализа - своего каталога у тестов нет.
private func makeSandbox() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("m3u-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// Пустой файл по месту: содержимое не нужно, парсеру важно только существование.
private func touch(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data().write(to: url)
}

private func makeTrack(_ url: URL, artist: String, title: String, duration: TimeInterval) -> Track {
    Track(
        url: url,
        title: title,
        artist: artist,
        album: "",
        year: nil,
        duration: duration,
        bitrate: nil,
        sampleRate: nil,
        format: "MP3",
        artwork: nil,
        isPlayed: false
    )
}

@Test("Экспорт → импорт: рядом с треками относительные пути, в чужой папке - абсолютные, #EXTINF с секундами")
func writeThenReadRoundTrip() throws {
    let root = try makeSandbox()
    let musicDir = root.appendingPathComponent("Music")
    let setsDir = musicDir.appendingPathComponent("sets")
    let first = musicDir.appendingPathComponent("01 First Track.mp3")
    let second = musicDir.appendingPathComponent("02 Second #2.mp3")
    let third = setsDir.appendingPathComponent("03 Third.mp3")
    try touch(first)
    try touch(second)
    try touch(third)

    let tracks = [
        makeTrack(first, artist: "Aphex Twin", title: "Xtal", duration: 211.4),
        makeTrack(second, artist: "", title: "Untitled", duration: 59.6),
        makeTrack(third, artist: "Boards of Canada", title: "Roygbiv", duration: 62),
    ]

    // Плейлист в папке треков: строки путей относительные, подпапка тоже относительная.
    let playlist = musicDir.appendingPathComponent("coolset.m3u8")
    try M3UPlaylist.write(tracks: tracks, to: playlist)
    let text = try String(contentsOf: playlist, encoding: .utf8)
    let expected = [
        "#EXTM3U",
        "#EXTINF:211,Aphex Twin - Xtal",
        "01 First Track.mp3",
        "#EXTINF:60,Untitled",
        "02 Second #2.mp3",
        "#EXTINF:62,Boards of Canada - Roygbiv",
        "sets/03 Third.mp3",
        "",
    ].joined(separator: "\n")
    #expect(text == expected)
    #expect(try M3UPlaylist.read(url: playlist) == [first, second, third])

    // Плейлист в чужой папке: тех же треков в нём нет - пишем абсолютные пути, а не `../Music`.
    let foreignDir = root.appendingPathComponent("playlists")
    try FileManager.default.createDirectory(at: foreignDir, withIntermediateDirectories: true)
    let foreign = foreignDir.appendingPathComponent("coolset.m3u8")
    try M3UPlaylist.write(tracks: tracks, to: foreign)
    let foreignText = try String(contentsOf: foreign, encoding: .utf8)
    #expect(!foreignText.contains(".."))
    #expect(foreignText.contains("\(first.path)\n"))
    #expect(foreignText.contains("\(third.path)\n"))
    #expect(try M3UPlaylist.read(url: foreign) == [first, second, third])

    // Тот же файл в переводах строк CRLF и в старых маковых CR: Apple Music пишет и так, и так
    // (research/09-playlists.md §1), парсер обязан съесть оба варианта.
    let crlf = musicDir.appendingPathComponent("crlf.m3u8")
    try Data(expected.replacingOccurrences(of: "\n", with: "\r\n").utf8).write(to: crlf)
    #expect(try M3UPlaylist.read(url: crlf) == [first, second, third])

    let cr = musicDir.appendingPathComponent("cr.m3u")
    try Data(expected.replacingOccurrences(of: "\n", with: "\r").utf8).write(to: cr)
    #expect(try M3UPlaylist.read(url: cr) == [first, second, third])
}

@Test("Плейлист без единого существующего трека, пустой плейлист и HLS-манифест - ошибки с причиной")
func readFailures() throws {
    let root = try makeSandbox()
    let dir = root.appendingPathComponent("sets")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let gone = dir.appendingPathComponent("gone.m3u8")
    try Data("#EXTM3U\n#EXTINF:1,One\none.mp3\n#EXTINF:2,Two\ntwo.mp3\n".utf8).write(to: gone)
    #expect(throws: M3UError.noTracks(file: "gone.m3u8", missing: 2)) {
        try M3UPlaylist.read(url: gone)
    }

    let empty = dir.appendingPathComponent("empty.m3u")
    try Data("#EXTM3U\n\n# только комментарий\n".utf8).write(to: empty)
    #expect(throws: M3UError.empty(file: "empty.m3u")) {
        try M3UPlaylist.read(url: empty)
    }

    // HLS - тоже .m3u8, но не список треков: его теги ловятся до разбора путей,
    // иначе манифест с одним отсутствующим сегментом выглядел бы как «файлов не найдено».
    let hls = dir.appendingPathComponent("stream.m3u8")
    try Data("#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\nsegment0.ts\n".utf8).write(to: hls)
    #expect(throws: M3UError.hlsManifest(file: "stream.m3u8")) {
        try M3UPlaylist.read(url: hls)
    }
}

@Test("Строка, начинающаяся с #, пишется абсолютным путём: комментарием её сделать нельзя")
func leadingHashGoesAbsolute() throws {
    let root = try makeSandbox()
    let track = root.appendingPathComponent("#1 hit.mp3")
    try touch(track)
    let playlist = root.appendingPathComponent("set.m3u8")
    try M3UPlaylist.write(tracks: [makeTrack(track, artist: "", title: "#1 hit", duration: 30)], to: playlist)

    let text = try String(contentsOf: playlist, encoding: .utf8)
    #expect(text == "#EXTM3U\n#EXTINF:30,#1 hit\n\(track.path)\n")
    #expect(try M3UPlaylist.read(url: playlist) == [track])
}

@Test("Относительный путь - только внутрь каталога плейлиста, наружу и на другом томе - nil")
func relativePathRules() {
    let dir = URL(fileURLWithPath: "/Volumes/Library/Music/Sets")
    #expect(M3UPlaylist.relativePath(of: URL(fileURLWithPath: "/Volumes/Library/Music/Sets/a.mp3"), from: dir)
        == "a.mp3")
    #expect(M3UPlaylist.relativePath(of: URL(fileURLWithPath: "/Volumes/Library/Music/Sets/sub/a.mp3"), from: dir)
        == "sub/a.mp3")
    // Наружу относительный путь не пишем: он ломается при переносе папки с плейлистом.
    #expect(M3UPlaylist.relativePath(of: URL(fileURLWithPath: "/Volumes/Library/Music/a.mp3"), from: dir) == nil)
    #expect(M3UPlaylist.relativePath(of: URL(fileURLWithPath: "/Volumes/Library/Vinyl/a.mp3"), from: dir) == nil)
    #expect(M3UPlaylist.relativePath(of: URL(fileURLWithPath: "/Volumes/USB/a.mp3"), from: dir) == nil)
    #expect(M3UPlaylist.relativePath(of: URL(fileURLWithPath: "/a.mp3"), from: dir) == nil)
    // Сам каталог - не файл, относительного пути у него нет.
    #expect(M3UPlaylist.relativePath(of: dir, from: dir) == nil)
}

@Test("PBT: имена с пробелами, юникодом и # переживают запись и чтение без потерь")
func roundTripProperties() async {
    let name = Gen<Character?>.element(of: Array("abZ 09#-.юЯжЁΩ")).map { $0! }.string(of: 1...12)
    await propertyCheck(input: name.array(of: 1...6)) { names in
        let root = try makeSandbox()
        let musicDir = root.appendingPathComponent("Music")
        let playlist = root.appendingPathComponent("set.m3u8")
        var tracks: [Track] = []
        for (index, basename) in names.enumerated() {
            let url = musicDir.appendingPathComponent("\(index) \(basename).mp3")
            try touch(url)
            tracks.append(makeTrack(url, artist: "A", title: basename, duration: Double(index)))
        }
        try M3UPlaylist.write(tracks: tracks, to: playlist)
        #expect(try M3UPlaylist.read(url: playlist) == tracks.map(\.url))
        try? FileManager.default.removeItem(at: root)
    }
}
