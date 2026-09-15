import Foundation

/// Кривая громкости фейдера (audio taper), решение владельца DECISIONS 2026-09-15 15:34:
/// «линейный слайдер почти не меняет громкость до ~15 %».
///
/// Ухо слышит громкость логарифмически, поэтому позиция ручки линейна по децибелам,
/// а не по амплитуде: `dB = -60 · (1 - p)`, `gain = 10^(dB/20)`. Середина хода (p = 0.5)
/// даёт -30 dB ≈ 0.0316 амплитуды - примерно «в два раза тише» на слух, а не 50 % амплитуды.
///
/// Ниже `silenceThreshold` фейдер молчит ровно: -60 dB - это 0.001 амплитуды, отличить
/// от тишины нельзя, зато «ручка в самом низу = звука нет» обязано выполняться точно.
public enum VolumeCurve {
    /// Динамический диапазон фейдера: позиция 0 (после порога) соответствует -60 dB.
    public static let minimumDecibels: Double = -60

    /// Нижний участок хода, на котором фейдер закрыт полностью.
    public static let silenceThreshold: Double = 0.02

    /// Позиция ручки 0…1 → усиление движка 0…1. Вход вне диапазона клампится.
    public static func gain(forPosition position: Double) -> Float {
        let p = clampPosition(position)
        guard p >= silenceThreshold else { return 0 }
        let decibels = minimumDecibels * (1 - p)
        return Float(pow(10, decibels / 20))
    }

    /// Усиление 0…1 → позиция ручки 0…1. Вход вне диапазона клампится,
    /// усиление ниже -60 dB (включая ровный ноль) даёт позицию 0.
    public static func position(forGain gain: Float) -> Double {
        let g = clampGain(Double(gain))
        guard g > 0 else { return 0 }
        let decibels = 20 * log10(g)
        guard decibels > minimumDecibels else { return 0 }
        return clampPosition(1 - decibels / minimumDecibels)
    }

    private static func clampPosition(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    private static func clampGain(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
