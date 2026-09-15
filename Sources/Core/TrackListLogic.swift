import Foundation

/// Фильтр, сортировка и статусная строка живут здесь, а не в UI: у таргета App нет
/// тест-таргета (структура пакета зафиксирована), поэтому всё проверяемое без окна - в Core.
public enum TrackFilter {
    /// Подстрока без учёта регистра и диакритики по title и artist
    /// (localizedStandardContains). Пустой/пробельный запрос возвращает вход как есть,
    /// порядок всегда сохраняется.
    public static func filter(_ tracks: [Track], query: String) -> [Track] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedStandardContains(query) || $0.artist.localizedStandardContains(query)
        }
    }
}

public enum TrackSortField: String, Sendable, CaseIterable {
    case played, number, title, artist, year, duration
}

public enum TrackSort {
    /// Стабильная сортировка. year == nil всегда в конце, в обе стороны.
    /// case number - это исходный порядок плейлиста (сортировка по индексу входного массива).
    public static func sorted(_ tracks: [Track], by field: TrackSortField, ascending: Bool) -> [Track] {
        if field == .number {
            return ascending ? tracks : tracks.reversed()
        }
        // Swift sorted нестабильна: равенство ключей явно отдаём меньшему индексу.
        // nil года - в конец до применения направления, иначе переворот утащит его наверх.
        return tracks.enumerated()
            .sorted {
                if field == .year {
                    if $0.element.year == nil, $1.element.year != nil { return false }
                    if $1.element.year == nil, $0.element.year != nil { return true }
                }
                let first: Track = ascending ? $0.element : $1.element
                let second: Track = ascending ? $1.element : $0.element
                if precedes(first, second, by: field) { return true }
                if precedes(second, first, by: field) { return false }
                return $0.offset < $1.offset
            }
            .map(\.element)
    }

    /// true, если a строго раньше b по полю; равенство отдаётся индексу (стабильность).
    private static func precedes(_ a: Track, _ b: Track, by field: TrackSortField) -> Bool {
        switch field {
        case .number:
            return false
        case .played:
            return !a.isPlayed && b.isPlayed
        case .title:
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        case .artist:
            return a.artist.localizedStandardCompare(b.artist) == .orderedAscending
        case .year:
            return precedesYear(a.year, b.year)
        case .duration:
            return a.duration < b.duration
        }
    }

    /// nil всегда позже любого года.
    private static func precedesYear(_ a: Int?, _ b: Int?) -> Bool {
        switch (a, b) {
        case (.none, .none): return false
        case (.none, .some): return false
        case (.some, .none): return true
        case let (.some(x), .some(y)): return x < y
        }
    }
}

public enum PlaylistSummary {
    /// "12 треков / 6:41:03"; пустой список - "0 треков / 0:00".
    public static func text(for tracks: [Track]) -> String {
        let total = tracks.reduce(0) { $0 + $1.duration }
        return "\(tracks.count) \(trackWord(tracks.count)) / \(formattedDuration(total))"
    }

    private static func trackWord(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if lastTwo >= 11, lastTwo <= 14 { return "треков" }
        if last == 1 { return "трек" }
        if last >= 2, last <= 4 { return "трека" }
        return "треков"
    }
}
