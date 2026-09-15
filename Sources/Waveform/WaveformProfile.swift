import Foundation

/// Полоса волны, готовая к отрисовке: на каждый пиксель - высота 0…1 и цвет столбика.
struct WaveformProfile: Equatable {
    var heights: [Float]
    var colors: [WaveformStyle.Color]

    /// Порядок операций из SPEC §5.3: ресемпл под ширину (энергетическое среднее) -> сглаживание
    /// огибающей -> компрессия амплитуды `max(low, mid, high)`.
    ///
    /// Высота и цвет считаются по разным шкалам, и это главное в этой функции:
    /// - высота - общий RMS (как в кэше): громкость трека во всех полосах сразу;
    /// - цвет - каждая полоса, нормированная по своему пику. Общий пик давил бы полосу `high`
    ///   (у мастеринга она тише баса в разы), и волна выходила бы одной тёплой гаммой без
    ///   синего - решение владельца 2026-09-15 13:5x: полный спектр как у Serato.
    static func make(
        low: [Float], mid: [Float], high: [Float], width: Int, style: WaveformStyle
    ) -> WaveformProfile {
        guard width > 0, !(low.isEmpty && mid.isEmpty && high.isEmpty) else {
            return WaveformProfile(heights: [], colors: [])
        }
        let bands = [low, mid, high].map {
            smoothed(resampled($0, width: width), radius: style.smoothingRadius)
        }
        let scales = bands.map(reference)
        var heights = [Float](repeating: 0, count: width)
        var colors = [WaveformStyle.Color](repeating: style.background, count: width)
        for index in 0..<width {
            heights[index] = style.compression.apply(
                max(bands[0][index], max(bands[1][index], bands[2][index])))
            colors[index] = style.mix(
                low: weight(bands[0][index], scale: scales[0]),
                mid: weight(bands[1][index], scale: scales[1]),
                high: weight(bands[2][index], scale: scales[2]))
        }
        return WaveformProfile(heights: heights, colors: colors)
    }

    /// Пик полосы, по которому она нормируется в цвете: каждая полоса - по своему максимуму,
    /// иначе общий пик давит верх (у мастеринга он тише баса на 15-20 дБ) и синего не видно.
    /// Тишина (пик 0) даёт вес 0.
    private static func reference(_ band: [Float]) -> Float { band.max() ?? 0 }

    /// Вес полосы в смеси цветов: 0…1 от своего пика.
    private static func weight(_ value: Float, scale: Float) -> Float {
        guard scale > 0, value.isFinite else { return 0 }
        return min(max(value / scale, 0), 1)
    }

    /// Скользящее среднее радиусом `radius` пикселей: огибающая вместо забора из одиночных пиков.
    /// Края обрабатываются усечённым окном, длина не меняется. Радиус 0 - вход как есть.
    static func smoothed(_ values: [Float], radius: Int) -> [Float] {
        guard radius > 0, values.count > 1 else { return values }
        var result = [Float](repeating: 0, count: values.count)
        for index in values.indices {
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            var sum: Float = 0
            for neighbour in lower...upper { sum += values[neighbour] }
            result[index] = sum / Float(upper - lower + 1)
        }
        return result
    }

    /// Пустая полоса - ровные нули нужной длины: ресемплер на пустом входе отдаёт пустой массив.
    private static func resampled(_ values: [Float], width: Int) -> [Float] {
        values.isEmpty ? [Float](repeating: 0, count: width) : WaveformResampler.resample(values, toWidth: width)
    }
}
