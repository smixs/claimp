import Core
import Foundation

/// In-memory плейлист T4: порядок, фильтр, сортировка. Персист - в T5 (PlayedStore).
@MainActor
final class PlaylistModel {
    var allTracks: [Track]
    var query = ""
    var sortField: TrackSortField?
    var ascending = true

    init(tracks: [Track] = []) {
        allTracks = tracks
    }

    /// Видимые строки: фильтр всегда, сортировка поверх. Ручной порядок = порядок allTracks.
    var displayed: [Track] {
        let filtered = TrackFilter.filter(allTracks, query: query)
        guard let sortField else { return filtered }
        return TrackSort.sorted(filtered, by: sortField, ascending: ascending)
    }

    /// Дроп заменяет плейлист целиком, сбрасывает сортировку и поиск.
    func replaceAll(_ tracks: [Track]) {
        allTracks = tracks
        sortField = nil
        ascending = true
        query = ""
    }

    /// Подставляет результат разбора в трек; false - трека уже нет в списке или значения те же.
    /// Тег анализом не перетирается: приоритет живёт в `Track.withAnalysis`.
    func applyAnalysis(url: URL, bpm: Double?, key: String?) -> Bool {
        guard let index = allTracks.firstIndex(where: { $0.url == url }) else { return false }
        let updated = allTracks[index].withAnalysis(bpm: bpm, key: key)
        guard updated != allTracks[index] else { return false }
        allTracks[index] = updated
        return true
    }

    func togglePlayed(url: URL) {
        guard let index = allTracks.firstIndex(where: { $0.url == url }) else { return }
        allTracks[index].isPlayed.toggle()
    }

    /// Только из списка. Файлы на диске не трогаются никогда.
    func remove(urls: Set<URL>) {
        allTracks.removeAll { urls.contains($0.url) }
    }

    /// Внутренний drag: новый порядок видимых строк; сортировка сбрасывается.
    /// Отфильтрованные строки дописываются в конец в старом относительном порядке.
    func applyManualOrder(urls: [URL]) {
        var byURL: [URL: Track] = [:]
        byURL.reserveCapacity(allTracks.count)
        for track in allTracks { byURL[track.url] = track }
        var next: [Track] = []
        next.reserveCapacity(allTracks.count)
        for url in urls {
            if let track = byURL.removeValue(forKey: url) { next.append(track) }
        }
        next += allTracks.filter { byURL[$0.url] != nil }
        allTracks = next
        sortField = nil
        ascending = true
    }

    /// Перестановка видимых строк: убрать moved, вставить перед строкой targetRow.
    func moveDisplayed(urls moved: [URL], toRow targetRow: Int) {
        var order = displayed.map(\.url)
        order.removeAll { moved.contains($0) }
        let clamped = min(max(targetRow, 0), order.count)
        order.insert(contentsOf: moved, at: clamped)
        applyManualOrder(urls: order)
    }
}
