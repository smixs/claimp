import Foundation

/// Стиль волны: цвета трёх полос, компрессия, сглаживание, яркости прогресса и геометрия курсора.
/// Единственное место, где живут эти числа: смена цвета - правка одной строки, переанализ не нужен.
public struct WaveformStyle: Sendable, Equatable {
    /// Цвет в sRGB, компоненты 0…1. Свой тип, чтобы модуль Waveform не тянул AppKit в расчёты.
    public struct Color: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// `#RRGGBB` без альфы: палитра волны непрозрачная, прозрачность задаётся яркостями.
        public init(hex: UInt32) {
            self.init(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255)
        }
    }

    /// Мягкая компрессия амплитуды: без неё отлимитированный мастер даёт прямоугольник.
    public enum Compression: Sendable, Equatable {
        case linear
        /// `x^exponent`; 0.5 = корень.
        case power(Double)
        /// Линейная шкала в децибелах: 0 на `floorDb` и ниже, 1 на 0 dBFS.
        case logarithmic(floorDb: Double)

        /// Вход и выход всегда 0…1; мусор на входе (NaN, минус) даёт 0.
        public func apply(_ value: Float) -> Float {
            guard value.isFinite else { return 0 }
            let clamped = min(max(value, 0), 1)
            switch self {
            case .linear:
                return clamped
            case .power(let exponent):
                return powf(clamped, Float(exponent))
            case .logarithmic(let floorDb):
                // Порог неотрицательный (шкалы нет) - это линейный случай, а не деление на ноль.
                guard clamped > 0, floorDb < 0 else { return clamped }
                let decibels = 20 * log10(Double(clamped))
                return Float(min(max((decibels - floorDb) / -floorDb, 0), 1))
            }
        }
    }

    /// Геометрия блока волны в точках. Те же правила, что у палитры: числа живут только здесь,
    /// в отрисовке и в окне литералов нет. Высота самой волны берётся от процента из настроек
    /// (`WaveformView.waveHeight(percent:)`), полоса времени от процента не зависит.
    public enum Geometry {
        /// Высота волны при 100 % (SPEC 4.1: сегодняшние 80 pt - это 80 %).
        public static let maxWaveHeight: CGFloat = 100
        /// Полоса с подписями времени под волной (SPEC 4.1).
        public static let timeStripHeight: CGFloat = 14
        /// Пауза, после которой размер считается устоявшимся и битмап перерисовывается точно.
        /// Пока владелец тянет окно или слайдер, кадры идут чаще, и волну тянет сам слой.
        public static let resizeSettleDelay: TimeInterval = 0.08
    }

    public var low: Color
    public var mid: Color
    public var high: Color
    /// Фон полосы волны; им же приглушается несыгранная часть.
    public var background: Color
    public var cursor: Color
    /// Осевая линия в пустом состоянии: пока данных нет, полоса не пустует (SPEC §6.12).
    public var emptyLine: Color
    public var compression: Compression
    /// Сглаживание огибающей, в пикселях; 0 - выключено.
    public var smoothingRadius: Int
    public var unplayedBrightness: Double
    public var playedBrightness: Double
    public var cursorWidth: CGFloat
    /// Поле сверху и снизу, чтобы пик не упирался в край полосы.
    public var verticalInset: CGFloat
    /// Тишина видна тонкой линией, а не пустотой.
    public var minimumBarHeight: CGFloat

    public init(
        low: Color,
        mid: Color,
        high: Color,
        background: Color,
        cursor: Color,
        emptyLine: Color,
        compression: Compression,
        smoothingRadius: Int,
        unplayedBrightness: Double,
        playedBrightness: Double,
        cursorWidth: CGFloat,
        verticalInset: CGFloat,
        minimumBarHeight: CGFloat
    ) {
        self.low = low
        self.mid = mid
        self.high = high
        self.background = background
        self.cursor = cursor
        self.emptyLine = emptyLine
        self.compression = compression
        self.smoothingRadius = smoothingRadius
        self.unplayedBrightness = unplayedBrightness
        self.playedBrightness = playedBrightness
        self.cursorWidth = cursorWidth
        self.verticalInset = verticalInset
        self.minimumBarHeight = minimumBarHeight
    }

    /// Палитра - чистые компоненты R/G/B (решения владельца 2026-09-15 13:33 и 13:5x):
    /// басы - красный, середина - зелёный, верхи - синий (глубокий синий, как синие участки
    /// эталона `research/owner-ref-serato-waveform.png`), смесь Mixxx даёт жёлтый (бас + середина),
    /// бирюзовый (середина + верх), маджентовый/розовый (бас + верх) и белый, когда звучит всё
    /// сразу - полный спектр как у Serato. Токены с одним полным каналом каждый: тогда смесь
    /// не уезжает в грязный оттенок, а промежуточные цвета получаются чистыми.
    /// Контраст на фоне `#2B2F3A` (WCAG): басы 3,34:1, середина 9,82:1, верх 1,56:1, курсор 10,12:1;
    /// у чистого синего контраст низкий по природе (тот же глубокий синий есть и в эталоне),
    /// а типичные смеси ярче порога: жёлтый 12,5:1, бирюзовый 11,0:1, розовый 4,3:1, белый 20:1.
    public static let `default` = WaveformStyle(
        low: Color(hex: 0xFF0000),
        mid: Color(hex: 0x00FF00),
        high: Color(hex: 0x0000FF),
        background: Color(hex: 0x2B2F3A),
        cursor: Color(hex: 0xDCE0EA),
        emptyLine: Color(hex: 0x4E5464),
        compression: .power(0.5),
        smoothingRadius: 2,
        unplayedBrightness: 0.45,
        playedBrightness: 1,
        cursorWidth: 1,
        verticalInset: 2,
        minimumBarHeight: 1)

    /// Одноцветная палитра (настройка ⌘, → Волна): все три полосы одним тоном, поэтому смесь
    /// Mixxx даёт ровный цвет, а динамику несёт только высота столбика. Тон - тот же приглушённый
    /// фиолетовый, что у акцента интерфейса: волна без спектра не должна спорить с окном.
    public static let monochrome: WaveformStyle = {
        var style = WaveformStyle.default
        let bar = Color(hex: 0xB397E4)
        style.low = bar
        style.mid = bar
        style.high = bar
        return style
    }()

    /// Цвет столбика - формула Mixxx
    /// (`src/waveform/renderers/waveformrendererrgb.cpp:159-182`): взвешенная сумма цветов полос,
    /// делённая на максимальную компоненту. Нормировка по максимуму - не косметика: без неё
    /// смесь полос выцветает в грязно-серый (среднее трёх цветов), а с ней цвет всегда яркий,
    /// а громкость несёт только высота столбика - так и выглядит обзорная волна Serato
    /// (решение владельца 2026-09-15 13:33: цвета волны яркие, приглушённая палитра - только
    /// для интерфейса). Пустая колонка даёт фон, а не NaN: деления на ноль нет.
    public func mix(low: Float, mid: Float, high: Float) -> Color {
        let lowWeight = Self.weight(low)
        let midWeight = Self.weight(mid)
        let highWeight = Self.weight(high)
        let red = lowWeight * self.low.red + midWeight * self.mid.red + highWeight * self.high.red
        let green = lowWeight * self.low.green + midWeight * self.mid.green + highWeight * self.high.green
        let blue = lowWeight * self.low.blue + midWeight * self.mid.blue + highWeight * self.high.blue
        let loudest = max(red, max(green, blue))
        guard loudest > 0 else { return background }
        return Color(red: red / loudest, green: green / loudest, blue: blue / loudest)
    }

    /// Вес полосы в смеси: нечисловое и отрицательное не считаем.
    private static func weight(_ value: Float) -> Double {
        guard value.isFinite, value > 0 else { return 0 }
        return Double(value)
    }
}
