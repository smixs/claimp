import Foundation
import Testing
import PropertyBased

@testable import Core

// Требует зависимость CoreTests -> PropertyBased в Package.swift (владелец - скелетчик T0).

private func pbtTracks(from strings: [String]) -> [Track] {
    stride(from: 0, to: strings.count, by: 2).map { i in
        Track(
            url: URL(fileURLWithPath: "/pbt/\(i).mp3"),
            title: strings[i],
            artist: i + 1 < strings.count ? strings[i + 1] : "",
            album: "",
            year: nil,
            duration: 120,
            bitrate: nil,
            sampleRate: nil,
            format: "MP3",
            artwork: nil,
            isPlayed: false
        )
    }
}

/// Результат - подпоследовательность входа: порядок сохранён, лишних дублей нет.
private func isSubsequence(_ sub: [Track], of full: [Track]) -> Bool {
    var rest = full[...]
    for track in sub {
        guard let idx = rest.firstIndex(of: track) else { return false }
        rest = rest[rest.index(after: idx)...]
    }
    return true
}

@Test("PBT: пустой запрос - тождество, порядок - подпоследовательность, регистр не влияет")
func trackFilterProperties() async {
    let strings = Gen.letterOrNumber.string(of: 0...12).array(of: 0...10)
    let queries = Gen.letterOrNumber.string(of: 0...8)
    await propertyCheck(input: strings, queries, Gen.bool()) { strings, query, usePrefix in
        let tracks = pbtTracks(from: strings)
        // Половину прогонов ищем префикс реального названия (непустые совпадения),
        // половину - случайную строку (часто пустой результат).
        let searched = (usePrefix && !strings.isEmpty) ? String(strings[0].prefix(3)) : query
        let result = TrackFilter.filter(tracks, query: searched)
        #expect(isSubsequence(result, of: tracks))
        #expect(result == TrackFilter.filter(tracks, query: searched.uppercased()))
        if searched.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            #expect(result == tracks)
        }
    }
}
