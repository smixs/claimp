import Foundation

/// Диапазон темпа, в который приводится результат анализа.
///
/// Угадать октаву темпа труднее, чем период: Apple на drum & bass отдаёт ровно половину
/// (85 вместо 170), и каталоги между собой тоже не согласны (research/06 §2.3). Лечится это
/// не «умным» порогом, а диапазоном шириной в октаву, как в Mixxx: результат удваивается или
/// делится пополам, пока не попадёт внутрь. Дефолт 90-180 (решение владельца 15.09 19:00):
/// D&B 170-175 попадает целиком, хаус 120-128 тоже.
public struct TempoRange: Sendable, Equatable {
    /// Нижняя граница; верхняя - ровно вдвое больше, так что любой темп приводится однозначно.
    public let lower: Double

    /// 90-180: рабочий диапазон владельца.
    public static let `default` = TempoRange(lower: 90)

    /// Граница обязана быть положительным конечным числом: иначе приведение не сходится.
    public init(lower: Double) {
        precondition(lower.isFinite && lower > 0, "нижняя граница диапазона темпа должна быть > 0")
        self.lower = lower
    }

    /// Верхняя граница, не включается.
    public var upper: Double { lower * 2 }

    /// Приведение темпа в [lower, upper): умножение и деление на два, других правок нет.
    /// Ноль, отрицательное, NaN и бесконечность - не темп: nil, а не подставленное значение.
    public func normalized(_ bpm: Double) -> Double? {
        guard bpm.isFinite, bpm > 0 else { return nil }
        var value = bpm
        while value < lower { value *= 2 }
        while value >= upper { value /= 2 }
        return value
    }
}
