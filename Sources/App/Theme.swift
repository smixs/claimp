import AppKit
import Core

/// Тема окна: плоская, тёмная, по стилистике research/owner-ref-neumorphism-dark.png
/// (палитра, типографика, пропорции, скругления), но без объёма - решение владельца
/// DECISIONS 2026-09-15 13:28: «неоморфизм отменён, максимально плоский, без теней».
///
/// Это единственное место в модуле App, где живут цвета, размеры, радиусы и шрифты.
/// Смена цвета = правка одной строки. Замеры пипеткой и контрасты снимались скриптом
/// вне репозитория (в публичное дерево не входит).
enum Theme {
    enum background {
        /// Фон окна: шапка, транспорт, таблица, статус, полоса поиска.
        static let base = NSColor.hex(0x2B2F3A)
    }

    enum surface {
        /// Поверхность светлее фона: кнопки транспорта, заголовки колонок, выделенная строка.
        static let raised = NSColor.hex(0x343948)
        /// Поверхность темнее фона: дорожка громкости, поле поиска, слот обложки.
        static let inset = NSColor.hex(0x1E222B)
    }

    enum text {
        /// Название трека, строки таблицы. Не чистый белый: белый в интерфейсе запрещён.
        static let primary = NSColor.hex(0xDCE0EA)
        /// Ошибка движка в статусной строке. Красный из семьи accent.pink, светлее для контраста:
        /// WCAG 5.31 на background.base, 4.57 на surface.raised (порог текста 4.5).
        static let danger = NSColor.hex(0xE78892)
        /// Исполнитель, техстрока, заголовки колонок, статус, второстепенные колонки.
        /// Светлее эталонного #9AA1B3 на шаг: на surface.raised (заголовки колонок) 9AA1B3 давал 4.45.
        static let secondary = NSColor.hex(0x9DA4B6)
    }

    enum accent {
        /// Заполнение и ручка громкости, активный транспорт, текст выделенной строки, рамка дропа.
        /// Светлее эталонного #A888E0 на шаг: на surface.raised (выделенная строка) A888E0 давал 3.98.
        static let violet = NSColor.hex(0xB397E4)
        /// Зажжённая лампочка «сыграно».
        static let pink = NSColor.hex(0xD2A5AD)
        /// Только декор, текстом не бывает (контур погашенной лампочки).
        /// Светлее эталонного #6E7486: тот давал 2.87 на base при пороге графики 3.0.
        static let gray = NSColor.hex(0x7D8294)
    }

    enum border {
        /// Шов под заголовками колонок, разделители.
        static let subtle = NSColor.hex(0x232733)
    }

    enum radius {
        /// Поле поиска, лунка кнопки, мелкие поверхности.
        static let small: CGFloat = 6
        /// Обложка в шапке: строго квадрат без скруглений (решение владельца 15.09).
        static let cover: CGFloat = 0
    }

    enum spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// Высоты и размеры из SPEC §4.1; геометрия окна темой не меняется.
    enum size {
        static let windowWidth: CGFloat = 500
        static let windowHeight: CGFloat = 760
        static let windowMinWidth: CGFloat = 420
        static let windowMinHeight: CGFloat = 600

        /// Верхний блок: обложка слева, справа текст и транспорт (правка владельца 13:5x).
        static let headerStrip: CGFloat = 164
        /// Квадрат обложки: высота блока минус одинаковые поля.
        static let cover: CGFloat = headerStrip - 2 * spacing.m
        static let transportStrip: CGFloat = 52
        static let statusStrip: CGFloat = 20
        static let searchStrip: CGFloat = 30

        /// Кнопки транспорта без подложек: квадратная зона клика, внутри только иконка.
        static let transportButton: CGFloat = 44
        static let playButton: CGFloat = 52
        static let transportGap: CGFloat = 0
        static let transportIcon: CGFloat = 16
        static let playIcon: CGFloat = 22

        /// Громкость - вертикальный фейдер (channel strip) справа от кнопок.
        /// Ширина колонки держит подпись VOLUME целиком.
        static let volumeColumn: CGFloat = 52
        /// Тонкая дорожка и ручка-капсула с тремя чёрточками (эталон owner-ref-fader-knob.png).
        static let volumeTrack: CGFloat = 4
        static let volumeKnobWidth: CGFloat = 14
        static let volumeKnobHeight: CGFloat = 26
        /// Чёрточки на ручке: отступ от краёв капсулы, толщина и просвет между ними.
        static let volumeGripInset: CGFloat = 4
        static let volumeGripThickness: CGFloat = 1
        static let volumeGripSpacing: CGFloat = 4

        /// Мягкая обрезка длинного текста: последние pt уходят в цвет фона.
        static let textFade: CGFloat = 24

        /// Титлбар прозрачный, контент начинается под ним.
        static let titlebar: CGFloat = 28
        /// Логотип Claimp: высота фиксирована, ширина по пропорциям файла;
        /// отступ слева - за светофорами окна.
        static let logoHeight: CGFloat = 18
        static let logoLeading: CGFloat = 78

        /// Плотный плейлист (решение владельца 15.09 17:57) с кеглем из настроек (⌘,):
        /// высота строки = высота глифов, без межстрочного воздуха (`PlaylistFont.rowHeight`).
        /// На дефолтных 11 pt это те же 13 pt, что были у прежних 9 pt.
        @MainActor static var row: CGFloat {
            CGFloat(PlaylistFont.rowHeight(forRow: SettingsStore.shared.value.playlistFontSize))
        }
        /// Лампочка и её контур уменьшены вместе со строкой, чтобы не упираться в края.
        static let lamp: CGFloat = 6
        static let lampBorder: CGFloat = 1
        static let hairline: CGFloat = 1
        static let dropBorder: CGFloat = 2

        /// Окно настроек (⌘,): одна колонка групп, ширина держит самую длинную подпись,
        /// высота - по содержимому. Вкладок нет (решение владельца 15.09 19:49).
        static let settingsWidth: CGFloat = 420
        /// Слайдеры настроек: дорожка и колонка с текущим значением справа от неё.
        static let settingsSlider: CGFloat = 170
        static let settingsValue: CGFloat = 54
        /// Колонка подписи слева от контрола: «Размер шрифта», «Диапазон BPM».
        static let settingsLabel: CGFloat = 150
    }

    /// Ширины колонок таблицы (SPEC §4.1): текстовые растут, остальные фиксированы.
    enum column {
        /// Ширины заданы для дефолтного кегля строки; при другом кегле фиксированные колонки
        /// масштабируются вместе с ним - цифры и «8A» не должны обрезаться (настройка ⌘,).
        @MainActor static func scaled(_ width: CGFloat) -> CGFloat {
            (width * CGFloat(PlaylistFont.scale(forRow: SettingsStore.shared.value.playlistFontSize)))
                .rounded()
        }

        /// Поля текста в ячейке и в заголовке: у плотной строки отступы меньше общих spacing.
        static let cellInset: CGFloat = 3
        static let played: CGFloat = 16
        static let number: CGFloat = 22
        /// Минимумы текстовых колонок подрезаны под девять колонок: сумма фиксированных
        /// (16+22+32+44+52+48+44 = 258) плюс 92 и 70 ровно укладывается в минимальные 420 pt окна.
        static let titleMin: CGFloat = 92
        /// Стартовая ширина: сумма колонок влезает в окно по умолчанию (500 pt),
        /// на широком окне таблица растягивает текстовые колонки сама.
        static let titleIdeal: CGFloat = 130
        static let titleMax: CGFloat = 800
        static let artistMin: CGFloat = 70
        static let artistIdeal: CGFloat = 100
        static let artistMax: CGFloat = 600
        static let year: CGFloat = 32
        static let duration: CGFloat = 44
        /// kbps целым числом.
        static let bitrate: CGFloat = 52
        /// Темп без дробной части.
        static let bpm: CGFloat = 48
        /// Тональность как в теге: "8A", "Am".
        static let key: CGFloat = 44
        /// Формат «оба» из настроек: "8A · Am" не влезает в 44 pt.
        static let keyBoth: CGFloat = 66
    }

    /// Типографика эталона: крупный жирный заголовок, лёгкие подписи.
    enum font {
        static var title: NSFont { .systemFont(ofSize: 17, weight: .bold) }
        static var artist: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        static var tech: NSFont { .systemFont(ofSize: 11, weight: .regular) }
        /// Кегль строки плейлиста живёт в настройках (⌘,), по умолчанию 11 pt - на 20 % больше
        /// прежних 9 (решение владельца 15.09 19:49). Границы и производные размеры - `PlaylistFont`.
        @MainActor static var rowSize: CGFloat {
            CGFloat(PlaylistFont.clamp(SettingsStore.shared.value.playlistFontSize))
        }
        @MainActor static var row: NSFont { .systemFont(ofSize: rowSize, weight: .regular) }
        @MainActor static var rowDigits: NSFont {
            .monospacedDigitSystemFont(ofSize: rowSize, weight: .regular)
        }
        /// Заголовки колонок - пропорция строки (было 8 pt при 9 pt строки).
        @MainActor static var columnHeader: NSFont {
            .systemFont(ofSize: CGFloat(PlaylistFont.headerSize(forRow: Double(rowSize))), weight: .regular)
        }
        /// Подписи и контролы окна настроек.
        static var control: NSFont { .systemFont(ofSize: 12, weight: .regular) }
        /// Заголовок группы в окне настроек.
        static var section: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
        /// Поле поиска: плотность плейлиста его не касается.
        static var search: NSFont { .systemFont(ofSize: 13, weight: .regular) }
        static var status: NSFont { .monospacedDigitSystemFont(ofSize: 11, weight: .regular) }
        /// Подписи фейдера: «VOL» и проценты.
        static var micro: NSFont { .systemFont(ofSize: 10, weight: .regular) }
        static var microDigits: NSFont { .monospacedDigitSystemFont(ofSize: 10, weight: .regular) }
    }

    /// Плоская заливка со скруглением - единственный приём оформления поверхностей.
    @MainActor static func fill(_ view: NSView, color: NSColor?, radius: CGFloat = 0) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.backgroundColor = color?.cgColor
        layer.cornerRadius = radius
        layer.masksToBounds = radius > 0
    }
}

extension NSColor {
    fileprivate static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
