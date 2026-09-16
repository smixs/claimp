import Foundation
import Testing

@testable import Core

private func logicTrack(
    _ file: String,
    title: String,
    artist: String,
    year: Int? = nil,
    duration: TimeInterval = 120,
    bitrate: Int? = nil,
    bpm: Double? = nil,
    key: String? = nil
) -> Track {
    Track(
        url: URL(fileURLWithPath: "/tmp/\(file)"),
        title: title,
        artist: artist,
        album: "",
        year: year,
        duration: duration,
        bitrate: bitrate,
        bpm: bpm,
        key: key,
        sampleRate: nil,
        format: "MP3",
        artwork: nil,
        isPlayed: false
    )
}

private let logicTracks = [
    logicTrack("a.mp3", title: "Future Garage Mix", artist: "Dj Antiz"),
    logicTrack("b.mp3", title: "Café del Mar", artist: "Energy 52"),
    logicTrack("c.mp3", title: "Silent Shout", artist: "The Knife"),
]

@Test("Пустой и пробельный запрос возвращают вход как есть")
func filterEmptyQueryIsIdentity() {
    #expect(TrackFilter.filter(logicTracks, query: "") == logicTracks)
    #expect(TrackFilter.filter(logicTracks, query: "   ") == logicTracks)
}

@Test("Фильтр ищет без учёта регистра и диакритики по названию и автору")
func filterMatchesCaseAndDiacriticInsensitive() {
    #expect(TrackFilter.filter(logicTracks, query: "antiz").count == 1)
    #expect(TrackFilter.filter(logicTracks, query: "CAFE").map(\.title) == ["Café del Mar"])
    #expect(TrackFilter.filter(logicTracks, query: "knife").map(\.title) == ["Silent Shout"])
    #expect(TrackFilter.filter(logicTracks, query: "no-such-track").isEmpty)
}

@Test("Фильтр сохраняет порядок входа")
func filterPreservesOrder() {
    let result = TrackFilter.filter(logicTracks, query: "e")
    #expect(result.map(\.title) == ["Future Garage Mix", "Café del Mar", "Silent Shout"])
}

@Test("Сортировка по длительности вверх и вниз даёт обратные последовательности")
func sortDurationBothWaysReverse() {
    let tracks = [
        logicTrack("a.mp3", title: "A", artist: "A", duration: 300),
        logicTrack("b.mp3", title: "B", artist: "B", duration: 120),
        logicTrack("c.mp3", title: "C", artist: "C", duration: 200),
    ]
    let asc = TrackSort.sorted(tracks, by: .duration, ascending: true).map(\.title)
    let desc = TrackSort.sorted(tracks, by: .duration, ascending: false).map(\.title)
    #expect(asc == ["B", "C", "A"])
    #expect(desc == asc.reversed())
}

@Test("Треки без года стоят в конце в обе стороны сортировки")
func sortYearNilGoesLastBothWays() {
    let tracks = [
        logicTrack("a.mp3", title: "A", artist: "A", year: nil),
        logicTrack("b.mp3", title: "B", artist: "B", year: 2015),
        logicTrack("c.mp3", title: "C", artist: "C", year: 1994),
    ]
    #expect(TrackSort.sorted(tracks, by: .year, ascending: true).map(\.title) == ["C", "B", "A"])
    #expect(TrackSort.sorted(tracks, by: .year, ascending: false).map(\.title) == ["B", "C", "A"])
}

@Test("Сортировка по номеру держит исходный порядок, вниз - обратный")
func sortNumberKeepsPlaylistOrder() {
    let asc = TrackSort.sorted(logicTracks, by: .number, ascending: true)
    #expect(asc.map(\.title) == logicTracks.map(\.title))
    let desc = TrackSort.sorted(logicTracks, by: .number, ascending: false)
    #expect(desc.map(\.title) == logicTracks.map(\.title).reversed())
}

@Test("Сортировки по названию, автору и лампочке")
func sortTitleArtistPlayed() {
    #expect(TrackSort.sorted(logicTracks, by: .title, ascending: true).map(\.title)
        == ["Café del Mar", "Future Garage Mix", "Silent Shout"])
    #expect(TrackSort.sorted(logicTracks, by: .artist, ascending: true).map(\.artist)
        == ["Dj Antiz", "Energy 52", "The Knife"])
    var played = logicTracks
    played[2].isPlayed = true
    #expect(TrackSort.sorted(played, by: .played, ascending: true).map(\.title)
        == ["Future Garage Mix", "Café del Mar", "Silent Shout"])
    #expect(TrackSort.sorted(played, by: .played, ascending: false).first?.title == "Silent Shout")
}

@Test("Статусная строка по-английски: число треков и суммарная длительность")
func summaryText() {
    func tracks(_ count: Int, each duration: TimeInterval) -> [Track] {
        (0..<count).map { logicTrack("\($0).mp3", title: "T\($0)", artist: "A", duration: duration) }
    }
    #expect(PlaylistSummary.text(for: []) == "0 tracks · 0:00")
    #expect(PlaylistSummary.text(for: tracks(1, each: 61)) == "1 track · 1:01")
    #expect(PlaylistSummary.text(for: tracks(2, each: 60)) == "2 tracks · 2:00")
    #expect(PlaylistSummary.text(for: tracks(21, each: 60)) == "21 tracks · 21:00")
}

@Test("Статусная строка: три трека на 1:32:41")
func summaryThreeTracksOverHour() {
    let tracks = [
        logicTrack("a.mp3", title: "A", artist: "A", duration: 3600),
        logicTrack("b.mp3", title: "B", artist: "B", duration: 1200),
        logicTrack("c.mp3", title: "C", artist: "C", duration: 761),
    ]
    #expect(PlaylistSummary.text(for: tracks) == "3 tracks · 1:32:41")
}


@Test("Сортировка по темпу: пустой BPM в конце в обе стороны")
func sortBPMNilGoesLastBothWays() {
    let tracks = [
        logicTrack("a.mp3", title: "A", artist: "A", bpm: nil),
        logicTrack("b.mp3", title: "B", artist: "B", bpm: 174),
        logicTrack("c.mp3", title: "C", artist: "C", bpm: 128),
    ]
    #expect(TrackSort.sorted(tracks, by: .bpm, ascending: true).map(\.title) == ["C", "B", "A"])
    #expect(TrackSort.sorted(tracks, by: .bpm, ascending: false).map(\.title) == ["B", "C", "A"])
}

@Test("Сортировка по тональности и битрейту: значения по порядку, пустые в конце")
func sortKeyAndBitrate() {
    let tracks = [
        logicTrack("a.mp3", title: "A", artist: "A", bitrate: nil, key: nil),
        logicTrack("b.mp3", title: "B", artist: "B", bitrate: 320, key: "10A"),
        logicTrack("c.mp3", title: "C", artist: "C", bitrate: 128, key: "8A"),
    ]
    #expect(TrackSort.sorted(tracks, by: .key, ascending: true).map(\.title) == ["C", "B", "A"])
    #expect(TrackSort.sorted(tracks, by: .key, ascending: false).map(\.title) == ["B", "C", "A"])
    #expect(TrackSort.sorted(tracks, by: .bitrate, ascending: true).map(\.title) == ["C", "B", "A"])
    #expect(TrackSort.sorted(tracks, by: .bitrate, ascending: false).map(\.title) == ["B", "C", "A"])
}

@Test("Колонки битрейта, темпа и тональности пустые, если тегов нет")
func emptyCellsWithoutTags() {
    let bare = logicTrack("a.mp3", title: "A", artist: "A")
    #expect(bare.displayBitrate == "")
    #expect(bare.displayBPM == "")
    #expect(bare.displayKey == "")
    let tagged = logicTrack("b.mp3", title: "B", artist: "B", bitrate: 320, bpm: 174.0, key: "8A")
    #expect(tagged.displayBitrate == "320")
    #expect(tagged.displayBPM == "174")
    #expect(tagged.displayKey == "8A")
}
