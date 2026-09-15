import CryptoKit
import Foundation

/// Кэш посчитанных волн на диске: второе открытие того же трека мгновенное.
public struct WaveformCache: Sendable {
    /// ~/Library/Caches/dev.shima.claimp/waveform/
    public static let `default` = WaveformCache(directory: defaultDirectory)

    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Промах (нет файла или нет ключа по атрибутам трека) - это `nil`: холодный трек просто
    /// посчитается. Нечитаемый или испорченный файл кэша - ошибка наверх с причиной, а не
    /// молчаливый промах (правило «фолбэков и тихих пропусков нет»).
    public func load(for url: URL) throws -> WaveformData? {
        guard let file = fileURL(for: url) else { return nil }
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try WaveformData.decoded(from: Data(contentsOf: file))
    }

    /// Запись тоже не глотается: не сложилось в папку кэша - ошибка наверх, а не тихий пропуск.
    /// Нет ключа (сам трек пропал) - записывать нечего: анализа к этому моменту уже не будет.
    public func store(_ data: WaveformData, for url: URL) throws {
        guard let file = fileURL(for: url) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.encoded().write(to: file, options: .atomic)
    }

    /// Ключ - путь плюс размер, время правки и версия формата. Ширина вьюхи в ключ не входит,
    /// поэтому ресайз окна не вызывает переанализ.
    func fileURL(for url: URL) -> URL? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? Int,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        let digest = SHA256.hash(data: Data(url.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let mtime = Int(modified.timeIntervalSince1970 * 1000)
        return directory.appendingPathComponent(
            "\(digest)-v\(WaveformData.formatVersion)-\(size)-\(mtime).wfm")
    }

    private static var defaultDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appending(path: "dev.shima.claimp/waveform", directoryHint: .isDirectory)
    }
}
