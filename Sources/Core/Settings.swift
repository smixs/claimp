import Foundation

/// Настройки приложения (окно ⌘,): что видно в плейлисте, каким кеглем оно набрано,
/// как считается BPM/тональность и как выглядит волна.
///
/// Хранилище одно - `UserDefaults` с префиксом `Claimp.`; в файлы ничего не пишется.
/// Модель типизированная и чистая: значения вне допустимого диапазона приводятся к границам
/// (`PlaylistFont.clamp`), незнакомый вариант перечисления читается как значение по умолчанию -
/// это нормализация чужого ввода, а не подмена обязательных данных.
public struct AppSettings: Equatable, Sendable {
    /// Ключи колонок плейлиста, спрятанных владельцем (`TrackSortField.rawValue`).
    /// Хранится именно скрытое: новая колонка появляется видимой, а не исчезает у старых.
    public var hiddenColumns: Set<String>
    /// Кегль строки плейлиста, pt.
    public var playlistFontSize: Double
    /// Считать BPM и тональность у треков без тега.
    public var autoAnalyze: Bool
    public var tempoRange: TempoRangePreset
    /// Треки длиннее этого (минуты) не анализируются: миксы считаются часами и не нужны.
    public var analysisMaxMinutes: Int
    public var keyFormat: KeyFormat
    public var wavePalette: WavePalette
    /// Яркость несыгранной части волны, 0…1.
    public var waveUnplayedBrightness: Double

    public init(
        hiddenColumns: Set<String>,
        playlistFontSize: Double,
        autoAnalyze: Bool,
        tempoRange: TempoRangePreset,
        analysisMaxMinutes: Int,
        keyFormat: KeyFormat,
        wavePalette: WavePalette,
        waveUnplayedBrightness: Double
    ) {
        self.hiddenColumns = hiddenColumns
        self.playlistFontSize = PlaylistFont.clamp(playlistFontSize)
        self.autoAnalyze = autoAnalyze
        self.tempoRange = tempoRange
        self.analysisMaxMinutes = Self.clampMinutes(analysisMaxMinutes)
        self.keyFormat = keyFormat
        self.wavePalette = wavePalette
        self.waveUnplayedBrightness = Self.clampBrightness(waveUnplayedBrightness)
    }

    /// Дефолты владельца (DECISIONS 2026-09-15 19:00 и 19:49): все колонки видны, кегль на 20 %
    /// больше прежних 9 pt, автоанализ включён, темп 90-180, миксы длиннее 15 минут мимо,
    /// тональность в Camelot, волна спектральная.
    public static let `default` = AppSettings(
        hiddenColumns: [],
        playlistFontSize: PlaylistFont.defaultSize,
        autoAnalyze: true,
        tempoRange: .wide,
        analysisMaxMinutes: 15,
        keyFormat: .camelot,
        wavePalette: .spectrum,
        waveUnplayedBrightness: WaveBrightness.default)

    /// Порог длины: меньше минуты не бывает, дольше суток бессмысленно.
    public static let minutesRange: ClosedRange<Int> = 1...60

    private static func clampMinutes(_ value: Int) -> Int {
        min(max(value, minutesRange.lowerBound), minutesRange.upperBound)
    }

    private static func clampBrightness(_ value: Double) -> Double {
        guard value.isFinite else { return WaveBrightness.default }
        return min(max(value, WaveBrightness.range.lowerBound), WaveBrightness.range.upperBound)
    }
}

/// Диапазон поиска темпа. Пресеты владельца: D&B живёт на 170, поэтому по умолчанию 90-180.
public enum TempoRangePreset: String, CaseIterable, Sendable {
    case narrow = "70-140"
    case medium = "85-170"
    case wide = "90-180"

    public var minimumBPM: Double {
        switch self {
        case .narrow: return 70
        case .medium: return 85
        case .wide: return 90
        }
    }

    public var maximumBPM: Double {
        switch self {
        case .narrow: return 140
        case .medium: return 170
        case .wide: return 180
        }
    }

    public var title: String { rawValue }
}

/// Как показывать тональность в колонке Key.
public enum KeyFormat: String, CaseIterable, Sendable {
    /// 8A - как у Serato и Rekordbox.
    case camelot
    /// Am - нота с ладом.
    case note
    /// 8A · Am.
    case both

    public var title: String {
        switch self {
        case .camelot: return "Camelot (8A)"
        case .note: return "Нота (Am)"
        case .both: return "Оба (8A · Am)"
        }
    }
}

/// Палитра волны: спектральная по полосам частот или одноцветная.
public enum WavePalette: String, CaseIterable, Sendable {
    case spectrum
    case single

    public var title: String {
        switch self {
        case .spectrum: return "Спектр"
        case .single: return "Одноцветная"
        }
    }
}

/// Границы яркости несыгранной части волны. Дефолт совпадает с `WaveformStyle.default`
/// (модуль Waveform темы не знает, поэтому число продублировано здесь одним токеном).
public enum WaveBrightness {
    public static let range: ClosedRange<Double> = 0.1...1
    public static let `default`: Double = 0.45
    public static let step: Double = 0.05
}

/// Кегль плейлиста и производные от него размеры. Чистые функции: настройка держит одно число,
/// всё остальное считается от него, поэтому в вьюхах нет ни одного размера.
public enum PlaylistFont {
    /// Допустимый кегль строки, pt (решение владельца 19:49: слайдер 8-16).
    public static let range: ClosedRange<Double> = 8...16
    /// По умолчанию на 20 % больше прежних 9 pt: 9 × 1,2 = 10,8 → 11.
    public static let defaultSize: Double = 11
    /// Заголовки колонок были 8 pt при строке 9 pt - эту пропорцию и держим.
    private static let headerRatio: Double = 8.0 / 9.0
    /// Высота глифов системного шрифта = (ascender − descender + leading) / кегль. Замер шагом
    /// 0,01 pt по всему диапазону 8…16 (`.scratch/work/evidence/t19/ratio.swift`): максимум
    /// 1,17774, берём 1,178 с запасом. Проверяется тестом против метрик NSFont, а не на веру.
    private static let glyphHeightRatio: Double = 1.178

    /// Кегль из настроек: вне диапазона прижимается к границе, мусор (NaN) - к значению по умолчанию.
    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultSize }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Во сколько раз кегль отличается от дефолтного: на столько же растут фиксированные
    /// колонки таблицы, иначе на 16 pt номер «10» обрезается в своих 22 pt.
    public static func scale(forRow size: Double) -> Double {
        clamp(size) / defaultSize
    }

    /// Кегль заголовка колонки: пропорционально строке, с округлением до половины пункта.
    public static func headerSize(forRow size: Double) -> Double {
        (clamp(size) * headerRatio * 2).rounded() / 2
    }

    /// Высота строки плейлиста: ровно столько, сколько занимают глифы, вверх до целого пункта.
    /// Межстрочного воздуха нет - плейлист остаётся плотным (решение владельца 17:57),
    /// но текст не режется: при 11 pt это те же 13 pt, что и сейчас.
    public static func rowHeight(forRow size: Double) -> Double {
        (clamp(size) * glyphHeightRatio).rounded(.up)
    }
}

/// Видимость колонок плейлиста.
public enum PlaylistColumns {
    /// Лампочка «сыграно» - главная функция плеера, её не прячут (решение владельца 09:50).
    public static let pinned: Set<String> = [TrackSortField.played.rawValue]

    /// Колонки, которые показывает таблица: исходный порядок, минус спрятанные.
    /// Закреплённая колонка остаётся, даже если её ключ попал в спрятанные.
    public static func visible(all: [String], hidden: Set<String>) -> [String] {
        all.filter { !hidden.contains($0) || pinned.contains($0) }
    }

    /// Колонку можно спрятать: закреплённые не предлагаются в настройках вовсе.
    public static func canHide(_ key: String) -> Bool {
        !pinned.contains(key)
    }
}

/// Ключи хранения. Одно место: разъезд строки в двух файлах даёт настройку, которая
/// пишется в один ключ, а читается из другого.
public enum SettingsKey {
    public static let prefix = "Claimp."
    public static let hiddenColumns = prefix + "playlist.hiddenColumns"
    public static let playlistFontSize = prefix + "playlist.fontSize"
    public static let autoAnalyze = prefix + "analysis.auto"
    public static let tempoRange = prefix + "analysis.tempoRange"
    public static let analysisMaxMinutes = prefix + "analysis.maxMinutes"
    public static let keyFormat = prefix + "analysis.keyFormat"
    public static let wavePalette = prefix + "wave.palette"
    public static let waveUnplayedBrightness = prefix + "wave.unplayedBrightness"

    /// Все ключи настроек: по ним же идёт сброс.
    public static let all = [
        hiddenColumns, playlistFontSize, autoAnalyze, tempoRange,
        analysisMaxMinutes, keyFormat, wavePalette, waveUnplayedBrightness,
    ]
}

extension AppSettings {
    /// Чтение из `UserDefaults`. Ключа нет - берётся значение по умолчанию; значение есть,
    /// но негодное (кегль 99, незнакомый пресет) - приводится к допустимому.
    public init(reading defaults: UserDefaults) {
        let fallback = AppSettings.default
        let stored = defaults.stringArray(forKey: SettingsKey.hiddenColumns)
        self.init(
            hiddenColumns: stored.map(Set.init) ?? fallback.hiddenColumns,
            playlistFontSize: defaults.object(forKey: SettingsKey.playlistFontSize) as? Double
                ?? fallback.playlistFontSize,
            autoAnalyze: defaults.object(forKey: SettingsKey.autoAnalyze) as? Bool ?? fallback.autoAnalyze,
            tempoRange: Self.read(defaults, SettingsKey.tempoRange) ?? fallback.tempoRange,
            analysisMaxMinutes: defaults.object(forKey: SettingsKey.analysisMaxMinutes) as? Int
                ?? fallback.analysisMaxMinutes,
            keyFormat: Self.read(defaults, SettingsKey.keyFormat) ?? fallback.keyFormat,
            wavePalette: Self.read(defaults, SettingsKey.wavePalette) ?? fallback.wavePalette,
            waveUnplayedBrightness: defaults.object(forKey: SettingsKey.waveUnplayedBrightness) as? Double
                ?? fallback.waveUnplayedBrightness)
    }

    /// Запись. Пишутся все ключи разом: частичная запись оставила бы половину настроек от прошлой версии.
    public func write(to defaults: UserDefaults) {
        defaults.set(Array(hiddenColumns).sorted(), forKey: SettingsKey.hiddenColumns)
        defaults.set(playlistFontSize, forKey: SettingsKey.playlistFontSize)
        defaults.set(autoAnalyze, forKey: SettingsKey.autoAnalyze)
        defaults.set(tempoRange.rawValue, forKey: SettingsKey.tempoRange)
        defaults.set(analysisMaxMinutes, forKey: SettingsKey.analysisMaxMinutes)
        defaults.set(keyFormat.rawValue, forKey: SettingsKey.keyFormat)
        defaults.set(wavePalette.rawValue, forKey: SettingsKey.wavePalette)
        defaults.set(waveUnplayedBrightness, forKey: SettingsKey.waveUnplayedBrightness)
    }

    private static func read<T: RawRepresentable>(_ defaults: UserDefaults, _ key: String) -> T?
    where T.RawValue == String {
        guard let raw = defaults.string(forKey: key) else { return nil }
        return T(rawValue: raw)
    }
}

/// Живые настройки приложения: одно значение на процесс, изменение рассылается нотификацией,
/// подписчики применяют его на лету (перезапуск не нужен).
@MainActor
public final class SettingsStore {
    /// Нотификация об изменении; объект - сам стор.
    public static let didChange = Notification.Name(SettingsKey.prefix + "settingsDidChange")
    public static let shared = SettingsStore(defaults: .standard)

    public private(set) var value: AppSettings
    private let defaults: UserDefaults
    private let center: NotificationCenter

    public init(defaults: UserDefaults, center: NotificationCenter = .default) {
        self.defaults = defaults
        self.center = center
        value = AppSettings(reading: defaults)
    }

    /// Правка настроек: пишется в UserDefaults и рассылается подписчикам.
    /// Ничего не изменилось - нотификации нет (иначе таблица перерисовывается на каждый тик слайдера).
    public func update(_ mutate: (inout AppSettings) -> Void) {
        var draft = value
        mutate(&draft)
        // Нормализация живёт в init: слайдер и поле ввода не обязаны знать про границы.
        let normalized = AppSettings(
            hiddenColumns: draft.hiddenColumns,
            playlistFontSize: draft.playlistFontSize,
            autoAnalyze: draft.autoAnalyze,
            tempoRange: draft.tempoRange,
            analysisMaxMinutes: draft.analysisMaxMinutes,
            keyFormat: draft.keyFormat,
            wavePalette: draft.wavePalette,
            waveUnplayedBrightness: draft.waveUnplayedBrightness)
        guard normalized != value else { return }
        value = normalized
        normalized.write(to: defaults)
        center.post(name: Self.didChange, object: self)
    }

    /// Сброс: ключи удаляются целиком, значение возвращается к дефолтам владельца.
    public func reset() {
        for key in SettingsKey.all { defaults.removeObject(forKey: key) }
        guard value != .default else { return }
        value = .default
        center.post(name: Self.didChange, object: self)
    }
}
