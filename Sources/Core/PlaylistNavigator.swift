import Foundation

/// Шов «конец трека - следующий»: чистые функции поверх видимого порядка строк,
/// чтобы покрывать тестом, а не только руками (у App нет тест-таргета).
public enum PlaylistNavigator {
    /// Следующий по порядку. Последний даёт nil (зацикливания нет),
    /// неизвестный url и пустой список дают первый/ничего.
    public static func next(after url: URL?, in urls: [URL]) -> URL? {
        guard !urls.isEmpty else { return nil }
        guard let url, let index = urls.firstIndex(of: url) else { return urls.first }
        let next = index + 1
        return next < urls.endIndex ? urls[next] : nil
    }

    /// Случайный следующий (кнопка Random, решение владельца 16.09 ~01:55): любой трек списка,
    /// кроме текущего. Один трек в списке - он же и следующий, пустой список - nil.
    /// Генератор параметром: в бою системный, в тесте сидированный - результат проверяется, а не
    /// принимается на веру.
    public static func random(
        excluding url: URL?,
        in urls: [URL],
        using generator: inout some RandomNumberGenerator
    ) -> URL? {
        guard !urls.isEmpty else { return nil }
        let candidates = urls.filter { $0 != url }
        guard !candidates.isEmpty else { return urls.first }
        return candidates.randomElement(using: &generator)
    }

    /// Предыдущий по порядку. Первый даёт nil, неизвестный url - последний.
    public static func previous(before url: URL?, in urls: [URL]) -> URL? {
        guard !urls.isEmpty else { return nil }
        guard let url, let index = urls.firstIndex(of: url) else { return urls.last }
        return index > urls.startIndex ? urls[index - 1] : nil
    }

    /// Какой трек показывают шапка и волна (решение владельца 2026-09-15 15:46): пока движок держит
    /// трек (играет или на паузе) - звучащий, без воспроизведения - выделенная строка. Играющий трек
    /// главнее выделения: иначе во время сведения в шапке виден один трек, а звучит другой.
    /// Чистая функция в Core: у App нет тест-таргета, а правило обязано быть покрыто тестом.
    public static func shown(playing: URL?, selected: URL?) -> URL? {
        playing ?? selected
    }

    /// Строки, которые надо перерисовать при смене играющего трека: старая и новая.
    /// Только они - таблица не перезагружается целиком, выделение и прокрутка остаются на месте.
    /// Тот же трек и трек, которого нет в видимом списке (отфильтрован поиском), строк не дают.
    public static func rowsToRepaint(from previous: URL?, to current: URL?, in urls: [URL]) -> [Int] {
        guard previous != current else { return [] }
        return [previous, current]
            .compactMap { $0 }
            .compactMap { urls.firstIndex(of: $0) }
            .sorted()
    }

    /// Восстановление плейлиста: отсутствующие на диске выбрасываются молча.
    /// Текущий трек, которого нет среди выживших, становится nil.
    public static func restore(
        urls: [URL],
        current: URL?,
        isExisting: (URL) -> Bool
    ) -> RestoredPlaylist {
        let surviving = urls.filter(isExisting)
        let kept = current.flatMap { surviving.contains($0) ? $0 : nil }
        return RestoredPlaylist(urls: surviving, current: kept)
    }
}

/// Результат восстановления плейлиста из базы.
public struct RestoredPlaylist: Sendable, Equatable {
    public let urls: [URL]
    public let current: URL?
    public init(urls: [URL], current: URL?) {
        self.urls = urls
        self.current = current
    }
}
