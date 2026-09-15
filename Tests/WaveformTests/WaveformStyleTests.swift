import Foundation
import PropertyBased
import Testing

@testable import Waveform

/// Все три шкалы компрессии: линейная, степенная и логарифмическая.
private let allCompressions: [WaveformStyle.Compression] = [
    .linear, .power(0.5), .logarithmic(floorDb: -48),
]

extension WaveformStyle.Color {
    /// Сравнение с допуском: смесь полос считается в Double.
    fileprivate func isClose(to other: WaveformStyle.Color, tolerance: Double = 1e-6) -> Bool {
        abs(red - other.red) < tolerance
            && abs(green - other.green) < tolerance
            && abs(blue - other.blue) < tolerance
    }

    /// Тот же оттенок, но с максимальной компонентой 1: что даёт нормировка Mixxx.
    fileprivate func normalized() -> WaveformStyle.Color {
        let loudest = max(red, max(green, blue))
        return WaveformStyle.Color(red: red / loudest, green: green / loudest, blue: blue / loudest)
    }
}

@Test("PBT: компрессия монотонна, держит 0…1 и не сдвигает края")
func compressionIsMonotonicAndBounded() async {
    let value = Gen.float(in: 0...1)

    await propertyCheck(count: 50, input: value, value) { first, second in
        let lower = min(first, second)
        let upper = max(first, second)
        for compression in allCompressions {
            let quiet = compression.apply(lower)
            let loud = compression.apply(upper)

            #expect(quiet <= loud)
            #expect(quiet >= 0 && quiet <= 1)
            #expect(loud >= 0 && loud <= 1)
            #expect(compression.apply(0) == 0)
            #expect(compression.apply(1) == 1)
        }
    }
}

@Test("Компрессия поднимает тихое: степенная и логарифмическая выше линейной")
func compressionLiftsQuietParts() {
    let quiet: Float = 0.05

    #expect(WaveformStyle.Compression.linear.apply(quiet) == quiet)
    #expect(WaveformStyle.Compression.power(0.5).apply(quiet) > 0.2)  // √0,05 ≈ 0,224
    #expect(WaveformStyle.Compression.logarithmic(floorDb: -48).apply(quiet) > 0.4)  // -26 дБ
}

@Test("Логарифмическая компрессия: ноль на пороге и ниже, единица на 0 dBFS")
func logarithmicCompressionHitsFloor() {
    let compression = WaveformStyle.Compression.logarithmic(floorDb: -48)

    #expect(compression.apply(0) == 0)
    #expect(compression.apply(0.001) == 0)  // -60 дБ, ниже порога
    #expect(abs(compression.apply(0.5) - 0.875) < 0.01)  // -6 дБ на шкале -48…0
    #expect(compression.apply(1) == 1)
}

@Test("PBT: сглаживание не меняет длину и не выходит за диапазон входа")
func smoothingKeepsLengthAndRange() async {
    let values = Gen.float(in: 0...1).array(of: 0...200)
    let radius = Gen.int(in: 0...8)

    await propertyCheck(count: 50, input: values, radius) { samples, radius in
        let smoothed = WaveformProfile.smoothed(samples, radius: radius)

        #expect(smoothed.count == samples.count)
        guard let lowest = samples.min(), let highest = samples.max() else { return }
        #expect(smoothed.allSatisfy { $0 >= lowest && $0 <= highest })
    }
}

@Test("Сглаживание нулевым радиусом ничего не меняет, пустой вход остаётся пустым")
func smoothingWithZeroRadiusIsIdentity() {
    let values: [Float] = [0, 1, 0, 0.5]

    #expect(WaveformProfile.smoothed(values, radius: 0) == values)
    #expect(WaveformProfile.smoothed([], radius: 4).isEmpty)
}

@Test("Сглаживание усредняет соседей усечённым окном на краях")
func smoothingAveragesNeighbours() {
    let values: [Float] = [1, 0, 0, 0, 1]

    // Радиус 1: края считаются по двум точкам, середина - по трём.
    let expected: [Float] = [0.5, 1.0 / 3, 0, 1.0 / 3, 0.5]
    let result = WaveformProfile.smoothed(values, radius: 1)

    #expect(result.count == expected.count)
    #expect(zip(result, expected).allSatisfy { abs($0 - $1) < 1e-6 })
}

@Test("Палитра из чистых компонент R/G/B: каждый токен - один полный канал")
func paletteIsSpectral() {
    let style = WaveformStyle.default

    #expect(style.low == WaveformStyle.Color(red: 1, green: 0, blue: 0))
    #expect(style.mid == WaveformStyle.Color(red: 0, green: 1, blue: 0))
    #expect(style.high == WaveformStyle.Color(red: 0, green: 0, blue: 1))
}

@Test("Смесь полос даёт полный спектр: жёлтый, бирюзовый и фиолетовый между чистых цветов")
func mixCoversWholeSpectrum() {
    let style = WaveformStyle.default

    let yellow = style.mix(low: 1, mid: 1, high: 0)  // бас + середина
    let cyan = style.mix(low: 0, mid: 1, high: 1)  // середина + верх
    let magenta = style.mix(low: 1, mid: 0, high: 1)  // бас + верх

    #expect(yellow.red > 0.8 && yellow.green > 0.8 && yellow.blue < 0.5)
    #expect(cyan.green > 0.8 && cyan.blue > 0.8 && cyan.red < 0.7)
    #expect(magenta.red > 0.8 && magenta.blue > 0.5 && magenta.green < 0.4)
}

@Test("Смеси полос различимы на фоне: контраст промежуточных цветов не ниже 3:1")
func paletteHasEnoughContrast() {
    let style = WaveformStyle.default
    // Глубокий синий из тех же соображений, что в эталоне, темнее порога - он и не должен быть ярким.
    let mixes: [(String, WaveformStyle.Color)] = [
        ("басы", style.mix(low: 1, mid: 0, high: 0)),
        ("середина", style.mix(low: 0, mid: 1, high: 0)),
        ("бас + середина", style.mix(low: 1, mid: 1, high: 0)),
        ("середина + верх", style.mix(low: 0, mid: 1, high: 1)),
        ("бас + верх", style.mix(low: 1, mid: 0, high: 1)),
        ("весь спектр", style.mix(low: 1, mid: 1, high: 1)),
    ]

    for (name, color) in mixes {
        let ratio = WaveformStyleContrast.ratio(color, style.background)
        // Измерено: басы 3,34:1, середина 9,82:1, жёлтый 12,5:1, бирюзовый 11,0:1, розовый 4,3:1, белый 20:1.
        #expect(ratio >= 3, "\(name): \(ratio):1")
    }
}

/// Контраст WCAG 2.x: палитра волны должна читаться на своём фоне.
private enum WaveformStyleContrast {
    static func ratio(_ first: WaveformStyle.Color, _ second: WaveformStyle.Color) -> Double {
        let firstLuminance = luminance(first)
        let secondLuminance = luminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private static func luminance(_ color: WaveformStyle.Color) -> Double {
        0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }

    private static func channel(_ component: Double) -> Double {
        component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

@Test("Смесь полос по формуле Mixxx: пропорции токена, максимальная компонента вытянута до 1")
func mixFollowsMixxxFormula() {
    let style = WaveformStyle.default

    // Чистая полоса - свой цвет токена, но яркий: максимальная компонента всегда 1.
    #expect(style.mix(low: 1, mid: 0, high: 0).isClose(to: style.low.normalized()))
    #expect(style.mix(low: 0, mid: 1, high: 0).isClose(to: style.mid.normalized()))
    #expect(style.mix(low: 0, mid: 0, high: 1).isClose(to: style.high.normalized()))
    // Тихая колонка того же спектра даёт тот же цвет: яркость считает нормировка, громкость - высота.
    #expect(style.mix(low: 0.05, mid: 0, high: 0).isClose(to: style.low.normalized()))
}

@Test("Смесь полос: любой непустой столбик яркий, пустой и мусорный дают фон")
func mixIsAlwaysVividOrBackground() {
    let style = WaveformStyle.default
    let mixes = [
        style.mix(low: 1, mid: 1, high: 0),
        style.mix(low: 0.4, mid: 0.2, high: 0.9),
        style.mix(low: 0.01, mid: 0.01, high: 0.01),
    ]

    for color in mixes {
        #expect(abs(max(color.red, max(color.green, color.blue)) - 1) < 1e-6)
    }
    // Ничьи полосы - это фон, а не чёрный NaN и не деление на ноль.
    #expect(style.mix(low: 0, mid: 0, high: 0) == style.background)
    #expect(style.mix(low: .nan, mid: -1, high: .infinity) == style.background)
}

@Test("Смесь равных полос даёт средний цвет, вытянутый до полной яркости")
func equalMixStaysVivid() {
    let style = WaveformStyle.default

    let mixed = style.mix(low: 1, mid: 1, high: 0)
    let average = WaveformStyle.Color(
        red: (style.low.red + style.mid.red) / 2,
        green: (style.low.green + style.mid.green) / 2,
        blue: (style.low.blue + style.mid.blue) / 2)

    #expect(mixed.isClose(to: average.normalized()))
}

@Test("Цвет полосы нормируется по своей полосе: тихий верх доезжает до цвета на фоне басов")
func profileReachesHighBandColor() {
    // Басы жмут свой пик весь трек, кроме окна, где играют только хай-хэты:
    // верх там на своём пике, но впятеро тише басов по уровню.
    var low = [Float](repeating: 1, count: 800)
    var high = [Float](repeating: 0, count: 800)
    for index in 400..<500 {
        low[index] = 0.02
        high[index] = 0.2
    }
    let mid = [Float](repeating: 0, count: 800)

    let profile = WaveformProfile.make(low: low, mid: mid, high: high, width: 100, style: .default)
    let hatColor = profile.colors[55]
    let bassColor = profile.colors[10]

    // Окно хай-хэтов - фиолетовое, а не оранжевое: иначе общий пик давит верх.
    #expect(hatColor.blue > 0.5)
    #expect(bassColor.blue < 0.2)
    // Высота при этом считается по общему RMS: тихий участок явно ниже громкого баса.
    #expect(profile.heights[55] < 0.6 * profile.heights[10])
}

@Test("Профиль волны: длина по ширине, тихое ниже громкого, цвет по полосе")
func profileKeepsDynamicsAndColor() {
    // Слева громкий бас, справа тишина: огибающая обязана это показать.
    var low = [Float](repeating: 0.9, count: 100)
    low += [Float](repeating: 0, count: 700)
    let mid = [Float](repeating: 0, count: 800)
    let high = [Float](repeating: 0, count: 800)

    let profile = WaveformProfile.make(low: low, mid: mid, high: high, width: 100, style: .default)

    #expect(profile.heights.count == 100)
    #expect(profile.colors.count == 100)
    #expect(profile.heights[10] > 0.9)  // √0,9 ≈ 0,949
    // Хвост сглаживания (радиус 2) и тишина явно ниже громкой части.
    #expect(profile.heights[90] < 0.1)
    #expect(profile.colors[10].isClose(to: WaveformStyle.default.low.normalized()))
}
