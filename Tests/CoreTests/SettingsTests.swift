import AppKit
import Foundation
import PropertyBased
import Testing

@testable import Core

/// Своё хранилище на каждый тест: боевые настройки владельца тесты не трогают.
private func makeDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
    guard let defaults = UserDefaults(suiteName: name) else {
        fatalError("не завёлся отдельный UserDefaults для теста")
    }
    return defaults
}

@Test("Настройки переживают запись и чтение через UserDefaults")
func settingsRoundTripThroughDefaults() {
    let defaults = makeDefaults()
    let settings = AppSettings(
        hiddenColumns: ["year", "bitrate"],
        playlistFontSize: 14,
        autoAnalyze: false,
        shuffle: true,
        tempoRange: .narrow,
        analysisMaxMinutes: 20,
        keyFormat: .both,
        wavePalette: .single,
        waveUnplayedBrightness: 0.7)

    settings.write(to: defaults)

    #expect(AppSettings(reading: defaults) == settings)
}

@Test("Негодные значения в хранилище приводятся к допустимым, а не пролезают в интерфейс")
func settingsNormalizeGarbageFromDefaults() {
    let defaults = makeDefaults()
    defaults.set(99.0, forKey: SettingsKey.playlistFontSize)
    defaults.set("500-600", forKey: SettingsKey.tempoRange)
    defaults.set(0, forKey: SettingsKey.analysisMaxMinutes)
    defaults.set(42.0, forKey: SettingsKey.waveUnplayedBrightness)

    let settings = AppSettings(reading: defaults)

    #expect(settings.playlistFontSize == PlaylistFont.range.upperBound)
    #expect(settings.tempoRange == AppSettings.default.tempoRange)
    #expect(settings.analysisMaxMinutes == AppSettings.minutesRange.lowerBound)
    #expect(settings.waveUnplayedBrightness == WaveBrightness.range.upperBound)
}

@Test("Дефолт: автоанализ выключен - пустые BPM и тональность остаются пустыми до правого клика")
func autoAnalyzeDefaultsOff() {
    #expect(AppSettings.default.autoAnalyze == false)
    // Пустое хранилище читается тем же дефолтом: после обновления ничего само не считается.
    #expect(AppSettings(reading: makeDefaults()).autoAnalyze == false)
}

@Test("Дефолт Random выключен, включённый переживает перезапуск")
func shuffleDefaultsOffAndSurvivesRestart() {
    #expect(AppSettings.default.shuffle == false)

    let defaults = makeDefaults()
    var settings = AppSettings.default
    settings.shuffle = true
    settings.write(to: defaults)

    #expect(AppSettings(reading: defaults).shuffle == true)
}

@Test("Дефолт: кегль на 20 % больше прежних 9 pt, строка остаётся 13 pt")
func defaultFontIsTwentyPercentLarger() {
    #expect(AppSettings.default.playlistFontSize == 11)
    #expect(PlaylistFont.rowHeight(forRow: 11) == 13)
    #expect(PlaylistFont.headerSize(forRow: 9) == 8)
    #expect(PlaylistFont.scale(forRow: 11) == 1)
    #expect(PlaylistFont.scale(forRow: 16) > 1)
}

@Test("Смена кегля масштабирует ручную ширину колонки, а не переписывает её токеном")
func columnWidthFollowsFontScale() {
    // Владелец сузил колонку до 30 pt при кегле 11; на 16 pt она должна вырасти в те же 16/11 раз.
    #expect(PlaylistFont.rescaled(width: 30, fromRow: 11, toRow: 16) == 44)
    #expect(PlaylistFont.rescaled(width: 30, fromRow: 11, toRow: 11) == 30)
}

@Test("Негодный кегль в пересчёте ширины прижимается к границе, а не даёт ноль или бесконечность")
func columnWidthRescaleClampsGarbageSizes() {
    // 99 pt и 2 pt в хранилище - это 16 и 8: ширина делится ровно пополам, а не уходит в мусор.
    #expect(PlaylistFont.rescaled(width: 40, fromRow: 99, toRow: 2) == 20)
    #expect(PlaylistFont.rescaled(width: 40, fromRow: .nan, toRow: .nan) == 40)
}

@Test("Спрятанные колонки уходят из списка, порядок остальных сохраняется")
func hiddenColumnsDisappearFromList() {
    let all = ["played", "number", "title", "artist", "year"]

    let visible = PlaylistColumns.visible(all: all, hidden: ["number", "year"])

    #expect(visible == ["played", "title", "artist"])
}

@Test("Лампочку спрятать нельзя: ключ в спрятанных её не убирает")
func pinnedColumnStaysVisible() {
    let all = ["played", "number", "title"]

    let visible = PlaylistColumns.visible(all: all, hidden: ["played", "number"])

    #expect(visible == ["played", "title"])
    #expect(PlaylistColumns.canHide("played") == false)
}

@Test("PBT: кегль из настроек всегда в допустимом диапазоне")
func fontScaleAlwaysInRange() async {
    await propertyCheck(input: Gen.double(in: -1e6...1e6)) { raw in
        let size = PlaylistFont.clamp(raw)
        #expect(PlaylistFont.range.contains(size))
        #expect(PlaylistFont.headerSize(forRow: raw) <= size)
    }
}

@Test("PBT: строка вмещает глифы своего кегля целиком и не выше их на пункт")
func rowHeightFitsRealFontMetrics() async {
    await propertyCheck(input: Gen.double(in: PlaylistFont.range)) { size in
        let font = NSFont.systemFont(ofSize: CGFloat(size), weight: .regular)
        let glyphs = Double(font.ascender - font.descender + font.leading)
        let height = PlaylistFont.rowHeight(forRow: size)
        // Текст влезает целиком...
        #expect(height >= glyphs)
        // ...и лишнего воздуха нет: не больше пункта сверх глифов (плюс сотая - запас на
        // разницу между замеренным коэффициентом и метрикой конкретного кегля).
        #expect(height < glyphs + 1.01)
    }
}

@MainActor
@Test("Стор рассылает изменение один раз и не шумит, когда значение то же")
func storeNotifiesOnlyOnRealChange() {
    let center = NotificationCenter()
    let store = SettingsStore(defaults: makeDefaults(), center: center)
    var changes = 0
    let token = center.addObserver(forName: SettingsStore.didChange, object: nil, queue: nil) { _ in
        changes += 1
    }
    defer { center.removeObserver(token) }

    store.update { $0.playlistFontSize = 13 }
    store.update { $0.playlistFontSize = 13 }

    #expect(changes == 1)
    #expect(store.value.playlistFontSize == 13)
}

@MainActor
@Test("Сброс возвращает дефолты и чистит ключи хранилища")
func resetClearsStoredKeys() {
    let defaults = makeDefaults()
    let store = SettingsStore(defaults: defaults, center: NotificationCenter())
    store.update {
        $0.playlistFontSize = 16
        $0.hiddenColumns = ["year"]
    }

    store.reset()

    #expect(store.value == .default)
    #expect(defaults.object(forKey: SettingsKey.playlistFontSize) == nil)
    #expect(defaults.object(forKey: SettingsKey.hiddenColumns) == nil)
}
