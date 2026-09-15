import Foundation

/// Чтение «сырых» тегов, которые SFBAudioEngine не раскладывает по своим свойствам:
/// темп (BPM) и тональность (musical key). Источник - словарь «имя тега → значение»:
/// его даёт и `AudioMetadata.additionalMetadata` (Xiph, APE), и метаданные AVFoundation
/// (ID3, MP4), поэтому разбор один на все контейнеры, без ветки на вендора.
public enum TagFields {
    /// Тональность: ID3v2 TKEY, Xiph INITIALKEY/KEY, MP4 ©key, APE KEY.
    /// Порядок = приоритет при нескольких тегах в одном файле.
    private static let keyNames = ["tkey", "initialkey", "key"]
    /// Темп: ID3v2 TBPM, Xiph/APE BPM, MP4 tmpo.
    private static let bpmNames = ["tbpm", "bpm", "tmpo"]

    /// Имя тега без пространства имён и регистра: "id3/TKEY" → "tkey",
    /// "itsk/%A9key" → "key", "INITIALKEY" → "initialkey".
    public static func normalizedName(_ raw: String) -> String {
        let tail = raw.split(separator: "/").last.map(String.init) ?? raw
        return tail.lowercased()
            .replacingOccurrences(of: "%a9", with: "")
            .replacingOccurrences(of: "©", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    /// true, если тег с таким именем хранит тональность (проверка до чтения значения).
    public static func isKeyName(_ raw: String) -> Bool {
        keyNames.contains(normalizedName(raw))
    }

    /// Тональность как записана в теге ("8A", "Am"), без нормализации написания.
    /// Нет тега или пустое значение - nil (пустая ячейка, никакого анализа).
    public static func musicalKey(in tags: [String: String]) -> String? {
        first(in: tags, names: keyNames, parse: musicalKey(from:))
    }

    /// Темп из строкового тега; мусор и неположительные значения - nil.
    public static func bpm(in tags: [String: String]) -> Double? {
        first(in: tags, names: bpmNames, parse: bpm(from:))
    }

    /// "174" → 174, "174.00" → 174, " 128 " → 128; "", "abc", "0", "-5", "99999" → nil.
    /// Верхняя граница 999: выше - заведомо мусор в теге, а не темп.
    public static func bpm(from raw: String?) -> Double? {
        guard let text = trimmed(raw), let value = Double(text) else { return nil }
        guard value.isFinite, value > 0, value < 1000 else { return nil }
        return value
    }

    /// Значение тега тональности: обрезка пробелов, пустое - nil.
    public static func musicalKey(from raw: String?) -> String? {
        trimmed(raw)
    }

    private static func first<Value>(
        in tags: [String: String],
        names: [String],
        parse: (String?) -> Value?
    ) -> Value? {
        let normalized = Dictionary(
            tags.map { (normalizedName($0.key), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        for name in names {
            if let value = parse(normalized[name]) { return value }
        }
        return nil
    }

    private static func trimmed(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
