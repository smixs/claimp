import Foundation

/// Одна строка плейлиста: то, что показывается в таблице и хранится в базе.
public struct Track: Sendable, Equatable, Identifiable {
    public var id: URL { url }

    /// Путь к файлу на диске - он же ключ записи в базе.
    public let url: URL
    /// Из тега; пусто в теге - имя файла без расширения.
    public let title: String
    /// Из тега; пусто в теге - "" (пустая ячейка).
    public let artist: String
    public let album: String
    /// Год из тега; пустой тег остаётся пустым (решение владельца 15.09.2026).
    public let year: Int?
    public let duration: TimeInterval
    /// kbps, округлённый.
    public let bitrate: Int?
    /// Hz.
    public let sampleRate: Int?
    /// "MP3", "FLAC", "WAV", "AIFF" - нормализованное имя формата из SFBAudioProperties.
    public let format: String
    /// Байты обложки как лежат в теге; nil = обложки нет.
    public let artwork: Data?
    /// Ручная лампочка «уже сыграно», её ставит человек, а не плеер.
    public var isPlayed: Bool

    public init(
        url: URL,
        title: String,
        artist: String,
        album: String,
        year: Int?,
        duration: TimeInterval,
        bitrate: Int?,
        sampleRate: Int?,
        format: String,
        artwork: Data?,
        isPlayed: Bool
    ) {
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.year = year
        self.duration = duration
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.format = format
        self.artwork = artwork
        self.isPlayed = isPlayed
    }

    /// Год для колонки таблицы: нет года в теге - пустая ячейка, не «0» и не «—».
    public var displayYear: String {
        guard let year else { return "" }
        return String(year)
    }

    /// "32:07", при часе и больше - "1:12:45".
    public var displayDuration: String {
        formattedDuration(duration)
    }

    /// "MP3 · 44 kHz · 320 kbps · 2014", пустые части пропускаются.
    public var headerSubtitle: String {
        var parts: [String] = []
        if !format.isEmpty { parts.append(format) }
        if let sampleRate, sampleRate > 0 {
            parts.append("\(Int((Double(sampleRate) / 1000).rounded())) kHz")
        }
        if let bitrate, bitrate > 0 { parts.append("\(bitrate) kbps") }
        if !displayYear.isEmpty { parts.append(displayYear) }
        return parts.joined(separator: " · ")
    }
}

/// "32:07", при часе и больше - "1:12:45". Общая для ячейки и статусной строки.
func formattedDuration(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}
