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
    case played, number, title, artist, year, duration, bitrate, bpm, key

    /// Идентификатор колонки таблицы (он же ключ NSSortDescriptor) → поле сортировки.
    /// Чужой ключ - nil: молча сортировать по номеру нельзя, клик просто игнорируется.
    public static func forColumnKey(_ key: String) -> TrackSortField? {
        TrackSortField(rawValue: key)
    }
}

public enum TrackSort {
    /// Стабильная сортировка. Пустое значение (год, битрейт, темп, тональность)
    /// всегда в конце, в обе стороны.
    /// case number - это исходный порядок плейлиста (сортировка по индексу входного массива).
    public static func sorted(_ tracks: [Track], by field: TrackSortField, ascending: Bool) -> [Track] {
        if field == .number {
            return ascending ? tracks : tracks.reversed()
        }
        // Swift sorted нестабильна: равенство ключей явно отдаём меньшему индексу.
        // Пустые значения - в конец до применения направления, иначе переворот утащит их наверх.
        return tracks.enumerated()
            .sorted {
                let firstMissing = isMissing($0.element, field)
                let secondMissing = isMissing($1.element, field)
                if firstMissing != secondMissing { return secondMissing }
                let first: Track = ascending ? $0.element : $1.element
                let second: Track = ascending ? $1.element : $0.element
                if precedes(first, second, by: field) { return true }
                if precedes(second, first, by: field) { return false }
                return $0.offset < $1.offset
            }
            .map(\.element)
    }

    /// true, если у трека поле пустое: такие строки всегда ниже заполненных.
    private static func isMissing(_ track: Track, _ field: TrackSortField) -> Bool {
        switch field {
        case .year: return track.year == nil
        case .bitrate: return track.bitrate == nil
        case .bpm: return track.bpm == nil
        case .key: return track.key == nil
        case .played, .number, .title, .artist, .duration: return false
        }
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
            return precedes(a.year, b.year)
        case .duration:
            return a.duration < b.duration
        case .bitrate:
            return precedes(a.bitrate, b.bitrate)
        case .bpm:
            return precedes(a.bpm, b.bpm)
        case .key:
            return precedesText(a.key, b.key)
        }
    }

    /// nil всегда позже любого значения (пустые строки уже отсеяны isMissing).
    private static func precedes<Value: Comparable>(_ a: Value?, _ b: Value?) -> Bool {
        switch (a, b) {
        case let (.some(x), .some(y)): return x < y
        case (.some, .none): return true
        case (.none, .some), (.none, .none): return false
        }
    }

    /// Тональность сравнивается как текст тега, человеческим порядком ("8A" < "10A").
    private static func precedesText(_ a: String?, _ b: String?) -> Bool {
        switch (a, b) {
        case let (.some(x), .some(y)): return x.localizedStandardCompare(y) == .orderedAscending
        case (.some, .none): return true
        case (.none, .some), (.none, .none): return false
        }
    }
}

/// Русское согласование числительного: "1 трек", "2 трека", "5 треков".
public enum RussianCount {
    public static func word(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let lastTwo = abs(count) % 100
        let last = abs(count) % 10
        if lastTwo >= 11, lastTwo <= 14 { return many }
        if last == 1 { return one }
        if last >= 2, last <= 4 { return few }
        return many
    }
}

public enum PlaylistSummary {
    /// "12 треков / 6:41:03"; пустой список - "0 треков / 0:00".
    public static func text(for tracks: [Track]) -> String {
        let total = tracks.reduce(0) { $0 + $1.duration }
        let word = RussianCount.word(tracks.count, "трек", "трека", "треков")
        return "\(tracks.count) \(word) / \(formattedDuration(total))"
    }
}
