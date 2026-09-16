import Foundation

/// Ошибки чтения и записи плейлиста. Здесь только данные - что случилось и с чем; видимую
/// строку для владельца собирает App (`Strings.Error.*`), причины от Foundation идут как есть.
public enum M3UError: Error, Equatable {
    /// Файл `.m3u8` с тегами `#EXT-X-`: это HLS-манифест (поток сегментов), а не список треков.
    case hlsManifest(file: String)
    /// В файле нет ни одной строки-пути: только комментарии и пустые строки.
    case empty(file: String)
    /// Пути в файле есть, но ни один из них не существует на диске.
    case noTracks(file: String, missing: Int)
    /// Файл не прочитался: нет доступа, каталог вместо файла, для `.m3u8` - не UTF-8.
    case unreadable(file: String, reason: String)
    /// Плейлист не записался: нет прав, нет каталога, диск.
    case unwritable(path: String, reason: String)
}

/// Что вышло из чтения: существующие файлы в порядке файла и всё, чего на диске не оказалось.
public struct M3UReadResult: Sendable, Equatable {
    /// Треки в порядке строк файла. Существование проверено, читаемость тегов - нет: это дело сканера.
    public let urls: [URL]
    /// Пути из файла, которых нет на диске (уже абсолютные) - для отчёта владельцу.
    public let missing: [URL]

    public init(urls: [URL], missing: [URL]) {
        self.urls = urls
        self.missing = missing
    }
}

/// M3U/M3U8: список путей к трекам (research/09-playlists.md §1, решение владельца 16.09.2026).
///
/// Где какой формат: на чтение принимаются оба расширения одним парсером, на запись - всегда
/// UTF-8 `.m3u8`. Разбор и сборка текста - чистые функции (`lines`, `resolve`, `relativePath`,
/// `document`), ввод-вывод только в `readResult` и `write`: их и проверяют живые тесты.
public enum M3UPlaylist {
    /// Пути существующих файлов в порядке файла. Форма из спеки; кому нужен ещё и список
    /// пропущенных, тот зовёт `readResult` (одна реализация на обе).
    public static func read(url: URL) throws -> [URL] {
        try readResult(url: url).urls
    }

    public static func readResult(url: URL) throws -> M3UReadResult {
        let file = url.lastPathComponent
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw M3UError.unreadable(file: file, reason: error.localizedDescription)
        }
        let text = try decode(data, pathExtension: url.pathExtension, file: file)
        let paths = try lines(in: text, file: file)
        guard !paths.isEmpty else { throw M3UError.empty(file: file) }

        let directory = url.deletingLastPathComponent()
        var urls: [URL] = []
        var missing: [URL] = []
        for path in paths {
            let candidate = resolve(path, relativeTo: directory)
            if isExistingFile(candidate) {
                urls.append(candidate)
            } else {
                missing.append(candidate)
            }
        }
        // Ни одного живого трека - это ошибка, а не «плейлист из ничего»: молча затирать
        // текущий плейлист пустым нельзя (правило «фолбэков и тихих пропусков нет»).
        guard !urls.isEmpty else { throw M3UError.noTracks(file: file, missing: missing.count) }
        return M3UReadResult(urls: urls, missing: missing)
    }

    /// Запись всегда в UTF-8 и всегда расширенным M3U: `#EXTM3U`, на трек `#EXTINF` и путь.
    /// Путь относительный от каталога плейлиста; если так не выходит (другой том, имя-ловушка) -
    /// абсолютный. Файл пишется атомарно: половина плейлиста на диске хуже, чем его отсутствие.
    public static func write(tracks: [Track], to url: URL) throws {
        let text = document(tracks: tracks, directory: url.deletingLastPathComponent())
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            throw M3UError.unwritable(path: url.path, reason: error.localizedDescription)
        }
    }

    /// Плейлист ли это по имени файла. Расширение, а не UTI: дроп и панель отдают URL до того,
    /// как LaunchServices что-то о них знает, а `.m3u` и `.m3u8` - ровно те два расширения формата.
    public static func isPlaylist(_ url: URL) -> Bool {
        ["m3u", "m3u8"].contains(url.pathExtension.lowercased())
    }

    // MARK: - Текст (чистые функции)

    /// UTF-8; для `.m3u` при негодном UTF-8 - одна попытка в `.isoLatin1` (у этого расширения
    /// нет обязательной кодировки, Wikipedia/M3U). `.m3u8` обязан быть UTF-8 - иначе ошибка
    /// с причиной, а не кракозябры в путях.
    static func decode(_ data: Data, pathExtension: String, file: String) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return stripBOM(utf8) }
        if pathExtension.lowercased() == "m3u", let latin = String(data: data, encoding: .isoLatin1) {
            return stripBOM(latin)
        }
        throw M3UError.unreadable(file: file, reason: "not UTF-8")
    }

    /// Метка порядка байтов в начале файла попадёт в первый путь, если её не срезать.
    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// Строки-пути: пустые и `#`-комментарии пропускаются, `#EXT-X-` - сразу ошибка.
    /// Разделители любые: `\n`, `\r\n` и старые маковые `\r` (Apple Music пишет и такие).
    static func lines(in text: String, file: String) throws -> [String] {
        var paths: [String] = []
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if line.hasPrefix("#EXT-X-") { throw M3UError.hlsManifest(file: file) }
                continue
            }
            paths.append(line)
        }
        return paths
    }

    /// `file://` и `/...` - абсолютные, всё остальное - относительно каталога плейлиста.
    /// Проценты в `file://` раскодируются: так пути и пишутся в этих ссылках.
    static func resolve(_ line: String, relativeTo directory: URL) -> URL {
        if line.lowercased().hasPrefix("file://") {
            let rest = String(line.dropFirst("file://".count))
            let path = rest.removingPercentEncoding ?? rest
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        if line.hasPrefix("/") {
            return URL(fileURLWithPath: line).standardizedFileURL
        }
        return directory.appendingPathComponent(line).standardizedFileURL
    }

    /// Путь файла относительно каталога плейлиста; nil - писать нельзя, путь будет абсолютным.
    ///
    /// Правило (PL-2b, решение владельца): относительный путь - только когда трек лежит **внутри**
    /// каталога плейлиста или в его подпапках. Наружу (`../Music/...`) не строим: такой плейлист
    /// ломается, стоит перенести папку с плейлистом, а абсолютный путь остаётся верным везде.
    /// Другой том под это же правило и попадает: там пути расходятся в первых компонентах.
    static func relativePath(of file: URL, from directory: URL) -> String? {
        let fileParts = file.standardizedFileURL.pathComponents
        let dirParts = directory.standardizedFileURL.pathComponents
        guard !fileParts.isEmpty, !dirParts.isEmpty, dirParts.count <= fileParts.count else { return nil }
        // Каталог плейлиста должен быть началом пути файла - иначе это путь наружу, а не внутрь.
        guard Array(fileParts.prefix(dirParts.count)) == dirParts else { return nil }
        let inside = fileParts[dirParts.count...]
        guard !inside.isEmpty else { return nil }
        return inside.joined(separator: "/")
    }

    /// Годится ли относительный путь строкой в файле: `#` в начале сделал бы из него
    /// комментарий, а крайние пробелы парсер срезает - и файл нашёлся бы не тот.
    static func isSafeLine(_ relative: String) -> Bool {
        !relative.hasPrefix("#") && relative == relative.trimmingCharacters(in: .whitespaces)
    }

    /// Полный текст плейлиста. Строка пути - относительно каталога файла плейлиста и только для
    /// треков внутри него; всё остальное (путь наружу, чужой том, имя-ловушка) - абсолютным путём.
    static func document(tracks: [Track], directory: URL) -> String {
        var lines = ["#EXTM3U"]
        lines.reserveCapacity(1 + tracks.count * 2)
        for track in tracks {
            lines.append("#EXTINF:\(seconds(track.duration)),\(displayName(track))")
            let relative = relativePath(of: track.url, from: directory)
            if let relative, isSafeLine(relative) {
                lines.append(relative)
            } else {
                lines.append(track.url.standardizedFileURL.path)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Секунды целым: `#EXTINF` не знает долей (округление, а не отбрасывание - 59.6 это минута).
    static func seconds(_ duration: TimeInterval) -> Int {
        guard duration.isFinite else { return 0 }
        return max(0, Int(duration.rounded()))
    }

    /// Имя для `#EXTINF`: «Артист - Название», без артиста - только название (спека PL-2).
    static func displayName(_ track: Track) -> String {
        track.artist.isEmpty ? track.title : "\(track.artist) - \(track.title)"
    }

    // MARK: - Диск

    /// Существование и обычность файла одним запросом, как в сканере: каталог в списке путей -
    /// не трек. Права не проверяем: нечитаемый файл отсеет сканер и скажет об этом сам.
    static func isExistingFile(_ url: URL) -> Bool {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey])
        } catch {
            return false
        }
        return values.isRegularFile == true
    }
}
