import AVFoundation
import Foundation
import SFBAudioEngine
import UniformTypeIdentifiers

public protocol LibraryScanning: Sendable {
    /// Рекурсивный обход папки, только аудио по UTType.audio, сортировка по имени файла
    /// (localizedStandardCompare). Нечитаемые файлы пропускаются молча, не роняют скан.
    func scan(folder: URL) async -> [Track]
    /// Тот же маппинг для одного файла; nil, если файл не аудио или не читается.
    func track(at url: URL) async -> Track?
}

public struct LibraryScanner: LibraryScanning, Sendable {
    public init() {}

    public func scan(folder: URL) async -> [Track] {
        // Весь скан целиком, включая обход папки, идёт внутри detached-задачи (SPEC §5.4):
        // задача не наследует актор вызывающего и не встаёт на его изоляцию, поэтому главный
        // поток занят сканом не дольше, чем уходит на постановку задачи, - сколько бы файлов
        // ни было в папке. Причина detached вместо группы - порядок результата уже зафиксирован
        // сортировкой, параллелизм не нужен: TagLib читает ~0.1 мс/файл.
        // AudioFile/AudioMetadata не Sendable: они создаются, разбираются в Track
        // и умирают внутри readTrack, границу задачи пересекает только Track.
        return await Task.detached(priority: .userInitiated) {
            let urls = Self.audioFiles(in: folder)
            var tracks: [Track] = []
            tracks.reserveCapacity(urls.count)
            for url in urls {
                if let track = await Self.readTrack(at: url) {
                    tracks.append(track)
                }
            }
            return tracks
        }.value
    }

    public func track(at url: URL) async -> Track? {
        guard Self.isAudioFile(url) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            await Self.readTrack(at: url)
        }.value
    }

    static func audioFiles(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentTypeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator {
            guard isAudioFile(url) else { continue }
            urls.append(url)
        }
        return urls.sorted {
            let byName = $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
            guard byName != .orderedSame else {
                return $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            return byName == .orderedAscending
        }
    }

    static func isAudioFile(_ url: URL) -> Bool {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
        } catch {
            return false
        }
        guard values.isRegularFile == true,
              let contentType = values.contentType
        else { return false }
        // Только conformance UTType.audio, по расширениям не фильтруем.
        return contentType.conforms(to: .audio)
    }

    /// Один файл в Track; nil, если не открылся или не прочитался (пропуск молча).
    static func readTrack(at url: URL) async -> Track? {
        // init(url:) бросает, если формат не распознан; read - если файл битый.
        // Оба случая по спеке пропускаются молча, скан не роняют.
        let file: AudioFile
        do {
            file = try AudioFile(url: url)
            try file.readPropertiesAndMetadata()
        } catch {
            return nil
        }
        let metadata = file.metadata
        let properties = file.properties
        // SFB возвращает YES и для мусора (TagLib ругается в лог, но файл "прочитан").
        // Файл без единой декодируемой секунды - нечитаемый: пропускаем молча.
        let duration = await validatedDuration(properties.duration, url: url)
        guard duration.isFinite, duration > 0 else { return nil }
        return Track(
            url: url,
            title: nonEmpty(metadata.title) ?? url.deletingPathExtension().lastPathComponent,
            artist: metadata.artist ?? "",
            album: metadata.albumTitle ?? "",
            year: YearParser.year(from: metadata.releaseDate),
            duration: duration,
            bitrate: rounded(properties.bitrate),
            sampleRate: rounded(properties.sampleRate),
            format: normalizedFormat(properties.formatName),
            artwork: cover(from: metadata),
            isPlayed: false
        )
    }

    /// TagLib врёт про длительность MP3 без Xing-заголовка (битрейт первого кадра).
    /// Арбитраж как у Petrichor validatedDuration: AVFoundation дёргается только при
    /// duration <= 0 || NaN || Infinite || < 1.0; чужое значение берём при расхождении > 1 с.
    static func validatedDuration(_ raw: TimeInterval?, url: URL) async -> TimeInterval {
        let duration = raw ?? 0
        let suspicious = duration <= 0 || duration.isNaN || duration.isInfinite || duration < 1.0
        guard suspicious else { return duration }
        let probed: Double
        do {
            probed = try await AVURLAsset(url: url).load(.duration).seconds
        } catch {
            // AVFoundation не помог - оставляем значение TagLib как есть.
            return duration
        }
        if probed.isFinite, probed > 0, abs(probed - duration) > 1.0 { return probed }
        return duration
    }

    /// TagLib отдаёт bitrate в kbps, sampleRate в Hz; нули/мусор TagLib не отдаёт вовсе.
    static func rounded(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Int(value.rounded())
    }

    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// formatName у SFB человекочитаемый: "MPEG-1 Layer III", "WAVE", "FLAC", "AIFF".
    /// Контракт хочет короткие "MP3"/"WAV", остальное отдаём как есть.
    static func normalizedFormat(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        if raw.hasPrefix("MPEG") { return "MP3" }
        if raw == "WAVE" { return "WAV" }
        return raw
    }

    /// Байты первой обложки, при наличии - лицевой; нет картинок - nil.
    static func cover(from metadata: AudioMetadata) -> Data? {
        let pictures = metadata.attachedPictures
        let picture = pictures.first { $0.type == .frontCover } ?? pictures.first
        guard let bytes = picture?.imageData, !bytes.isEmpty else { return nil }
        return bytes
    }
}
