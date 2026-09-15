import Core
import Foundation

/// Тональность трека: двенадцать тонических классов и лад.
///
/// Apple отдаёт тонику семнадцатью именами (энгармонические пары `aFlat`/`gSharp`,
/// `bFlat`/`aSharp`, `dFlat`/`cSharp`, `dSharp`/`eFlat`, `gFlat`/`fSharp` приходят обеими
/// записями), поэтому свёртка в двенадцать классов - наша работа: иначе одна и та же
/// тональность показывалась бы в колонке двумя разными подписями.
public struct MusicalKey: Sendable, Equatable, Hashable {
    /// Тонический класс: номер полутона от C (C = 0 … B = 11).
    public enum Tonic: Int, Sendable, Equatable, Hashable, CaseIterable {
        case c = 0, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b
    }

    public enum Mode: String, Sendable, Equatable, Hashable, CaseIterable {
        case major, minor
    }

    /// Все семнадцать имён тоники Apple → номер полутона. Список закрытый: незнакомое имя
    /// не сворачивается молча в C, а возвращает nil (вызывающий обязан сказать об этом вслух).
    static let appleTonicSemitones: [String: Int] = [
        "c": 0, "cSharp": 1, "dFlat": 1, "d": 2, "dSharp": 3, "eFlat": 3, "e": 4,
        "f": 5, "fSharp": 6, "gFlat": 6, "g": 7, "gSharp": 8, "aFlat": 8, "a": 9,
        "aSharp": 10, "bFlat": 10, "b": 11,
    ]

    /// Подписи тоники через диезы: колонка и подсказка пишут одну запись из пары.
    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    public let tonic: Tonic
    public let mode: Mode

    public init(tonic: Tonic, mode: Mode) {
        self.tonic = tonic
        self.mode = mode
    }

    /// Свёртка имени Apple (`KeyResult.Tonic.rawValue`, `Mode.rawValue`) в наш класс.
    /// Незнакомое имя - nil.
    public init?(appleTonicName: String, modeName: String) {
        guard let semitone = Self.appleTonicSemitones[appleTonicName],
              let tonic = Tonic(rawValue: semitone),
              let mode = Mode(rawValue: modeName)
        else { return nil }
        self.init(tonic: tonic, mode: mode)
    }

    /// Код Camelot: "8A" (Am), "8B" (C). Номер - шаг по кварто-квинтовому кругу от C/Am,
    /// буква - лад. Считается формулой, а не таблицей из 24 строк: круг и есть умножение на 7.
    public var camelot: String {
        "\(Self.wheelNumber(relativeMajor: relativeMajorSemitone))\(mode == .minor ? "A" : "B")"
    }

    /// Человеческая подпись: "Am", "F#m", "C".
    public var shortName: String {
        Self.sharpNames[tonic.rawValue] + (mode == .minor ? "m" : "")
    }

    /// Подпись для колонки Key в формате из настроек (⌘, → Анализ → формат тональности).
    public func display(_ format: KeyFormat) -> String {
        switch format {
        case .camelot: return camelot
        case .note: return shortName
        case .both: return "\(camelot) · \(shortName)"
        }
    }

    /// Разбор кода Camelot обратно в тональность: "8A" → Am. Мусор и номера вне 1…12 - nil.
    public init?(camelot: String) {
        let text = camelot.trimmingCharacters(in: .whitespaces).uppercased()
        guard let letter = text.last, let mode = Mode(camelotLetter: letter),
              let number = Int(text.dropLast()), (1...12).contains(number)
        else { return nil }
        let relativeMajor = Self.relativeMajorSemitone(wheelNumber: number)
        let semitone = mode == .minor ? (relativeMajor + 9) % 12 : relativeMajor
        guard let tonic = Tonic(rawValue: semitone) else { return nil }
        self.init(tonic: tonic, mode: mode)
    }

    /// Параллельный мажор минорной тональности: у них общий номер на круге (Am и C - оба 8).
    private var relativeMajorSemitone: Int {
        mode == .minor ? (tonic.rawValue + 3) % 12 : tonic.rawValue
    }

    /// Номер на круге по мажорной тонике: C = 8, дальше по квинтам (умножение на 7 полутонов).
    private static func wheelNumber(relativeMajor semitone: Int) -> Int {
        (7 * semitone + 7) % 12 + 1
    }

    /// Обратная к `wheelNumber`: 7 - обратный элемент самому себе по модулю 12 (7 × 7 = 49 ≡ 1).
    private static func relativeMajorSemitone(wheelNumber number: Int) -> Int {
        (7 * (number - 8) % 12 + 12) % 12
    }
}

private extension MusicalKey.Mode {
    /// Буква Camelot: A - минор, B - мажор.
    init?(camelotLetter letter: Character) {
        switch letter {
        case "A": self = .minor
        case "B": self = .major
        default: return nil
        }
    }
}
