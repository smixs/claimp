import Foundation

/// Границы одной колонки таблицы и её участие в раздаче лишней ширины окна.
public struct ColumnWidthLimits: Sendable, Equatable {
    public let minWidth: CGFloat
    public let maxWidth: CGFloat
    /// Колонка забирает и отдаёт остаток ширины окна (Название, Исполнитель).
    public let isElastic: Bool

    public init(minWidth: CGFloat, maxWidth: CGFloat, isElastic: Bool) {
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.isElastic = isElastic
    }
}

/// Протяжку разделителя AppKit не компенсирует: меняется только колонка слева от границы,
/// а таблица становится шире окна (замеры research/07 §1.2, блок C). Здесь считается, кто
/// отдаёт или забирает эту дельту, чтобы сумма ширин осталась равной ширине таблицы.
public enum ColumnWidthBalancer {
    /// Ширины после протяжки границы.
    ///
    /// - Parameters:
    ///   - delta: насколько владелец потянул границу (плюс - колонка растёт).
    ///   - resizedIndex: индекс потянутой колонки в видимом порядке.
    ///   - widths: ширины видимых колонок ДО протяжки, в видимом порядке.
    ///   - limits: коридоры тех же колонок, тем же порядком.
    ///
    /// Правило: дельту гасит соседка справа, за ней следующие справа, в конце - эластичные
    /// слева (ближняя первой: Исполнитель, потом Название). Что раздать не вышло - на столько
    /// же урезается сама протяжка, поэтому сумма ширин не меняется.
    public static func redistribute(
        delta: CGFloat,
        resizedIndex: Int,
        widths: [CGFloat],
        limits: [ColumnWidthLimits]
    ) -> [CGFloat] {
        precondition(widths.count == limits.count, "ширины и коридоры разной длины")
        precondition(widths.indices.contains(resizedIndex), "потянутой колонки нет в списке")
        let own = limits[resizedIndex]
        let target = min(max(widths[resizedIndex] + delta, own.minWidth), own.maxWidth)
        let wanted = target - widths[resizedIndex]
        guard wanted != 0 else { return widths }

        var result = widths
        var remaining = wanted
        for donor in donorOrder(resizedIndex: resizedIndex, limits: limits) {
            guard remaining != 0 else { break }
            let room = remaining > 0
                ? widths[donor] - limits[donor].minWidth
                : limits[donor].maxWidth - widths[donor]
            let moved = min(abs(remaining), max(0, room))
            result[donor] = remaining > 0 ? widths[donor] - moved : widths[donor] + moved
            remaining = remaining > 0 ? remaining - moved : remaining + moved
        }
        result[resizedIndex] = widths[resizedIndex] + (wanted - remaining)
        return result
    }

    /// Соседка справа, дальше вправо до конца, затем эластичные слева - ближняя первой.
    private static func donorOrder(resizedIndex: Int, limits: [ColumnWidthLimits]) -> [Int] {
        let toTheRight = Array((resizedIndex + 1)..<limits.count)
        let elasticToTheLeft = (0..<resizedIndex).reversed().filter { limits[$0].isElastic }
        return toTheRight + elasticToTheLeft
    }
}
