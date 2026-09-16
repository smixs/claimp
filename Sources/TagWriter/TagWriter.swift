import CTagWriter
import Foundation

/// Тег не записан: файл и причина от TagLib. Тихого пропуска нет - ошибка идёт наверх,
/// владелец видит счётчик в статусной строке.
public struct TagWriteFailure: Error, Sendable, CustomStringConvertible {
    public let url: URL
    public let reason: String

    public init(url: URL, reason: String) {
        self.url = url
        self.reason = reason
    }

    public var description: String {
        "tag write failed: \(url.lastPathComponent) (\(reason))"
    }
}

/// Запись результата анализа в теги файла (решение владельца 16.09.2026 ~07:00):
/// нажал «Analyze» - значения ушли в файл, как у DJ-софта. Источник правды - тег,
/// кэш в базе остаётся ускорителем.
///
/// Раскладкой по контейнерам занимается TagLib: ID3v2 TBPM/TKEY для MP3, AIFF и WAV,
/// Vorbis comments BPM/INITIALKEY для FLAC, tmpo и `----:com.apple.iTunes:INITIALKEY` для MP4.
public enum TagWriter {
    /// Пишет темп и тональность в теги `url`. nil-поле не трогается; оба nil - работы нет.
    /// Остальные теги файла остаются прежними.
    public static func write(bpm: Double?, key: String?, to url: URL) throws {
        let bpmText = try bpm.map { value in
            guard let text = formatted(bpm: value) else {
                throw TagWriteFailure(url: url, reason: "\(value) is not a tempo")
            }
            return text
        }
        let keyText = try key.map { value in
            guard let text = trimmed(key: value) else {
                throw TagWriteFailure(url: url, reason: "musical key is empty")
            }
            return text
        }
        guard bpmText != nil || keyText != nil else { return }
        do {
            try CLPTagWriter.write(bpm: bpmText, key: keyText, to: url)
        } catch {
            throw TagWriteFailure(url: url, reason: error.localizedDescription)
        }
    }

    /// Темп в теге - целое число ("174"): ID3v2 TBPM и MP4 tmpo дробь всё равно не сохранят,
    /// так же округляют Mixxx и Rekordbox. Не-темп (NaN, ноль, минус, заведомый мусор) - nil.
    /// Границы те же, что у читателя `TagFields.bpm`: что пишем, то и прочитаем обратно.
    public static func formatted(bpm: Double) -> String? {
        guard bpm.isFinite, bpm > 0, bpm < 1000 else { return nil }
        return String(Int(bpm.rounded()))
    }

    /// Тональность пишется как дано ("Am", "F#m"), только без краевых пробелов.
    /// Пустая строка стёрла бы чужой тег молча - это не запись, а потеря данных.
    public static func trimmed(key: String) -> String? {
        let text = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
