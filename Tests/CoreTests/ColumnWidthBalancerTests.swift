import Foundation
import Testing
import PropertyBased

@testable import Core

private func limits(_ low: CGFloat, _ high: CGFloat, elastic: Bool = false) -> ColumnWidthLimits {
    ColumnWidthLimits(minWidth: low, maxWidth: high, isElastic: elastic)
}

/// Пять колонок как в плейлисте: две эластичные (Название, Исполнитель) и три числовые.
private let playlistLike = [
    limits(120, 800, elastic: true),
    limits(90, 800, elastic: true),
    limits(32, 48),
    limits(44, 64),
    limits(40, 72),
]

@Test("Протяжку вправо гасит соседка справа, остальные колонки на месте")
func neighbourAbsorbsDelta() {
    let widths: [CGFloat] = [130, 100, 40, 44, 70]
    let result = ColumnWidthBalancer.redistribute(
        delta: 20, resizedIndex: 3, widths: widths, limits: playlistLike)
    #expect(result == [130, 100, 40, 64, 50])
}

@Test("Протяжка влево: правая соседка растёт - так оттягивается крайняя Key")
func neighbourGrowsOnShrink() {
    let widths: [CGFloat] = [130, 100, 40, 64, 40]
    let result = ColumnWidthBalancer.redistribute(
        delta: -20, resizedIndex: 3, widths: widths, limits: playlistLike)
    #expect(result == [130, 100, 40, 44, 60])
}

@Test("Соседка у минимума: дельта уходит следующей справа, остаток - эластичной слева")
func deltaFallsThroughToElastic() {
    let widths: [CGFloat] = [130, 100, 40, 44, 50]
    let result = ColumnWidthBalancer.redistribute(
        delta: 20, resizedIndex: 1, widths: widths, limits: playlistLike)
    // Год отдаёт свои 8 (40 → 32), Длительность уже в минимуме, Key отдаёт 10 (50 → 40),
    // последние 2 pt берём у эластичного Названия слева.
    #expect(result == [128, 120, 32, 44, 40])
}

@Test("Раздать нечего: допустимая дельта 0, ширины не меняются")
func nothingToRedistribute() {
    let widths: [CGFloat] = [120, 90, 40, 44, 40]
    let result = ColumnWidthBalancer.redistribute(
        delta: 20, resizedIndex: 2, widths: widths, limits: playlistLike)
    #expect(result == widths)
}

@Test("Потянутая колонка не выходит за свой коридор, сумма ширин сохраняется")
func ownCorridorIsRespected() {
    let widths: [CGFloat] = [400, 200, 40, 50, 50]
    let result = ColumnWidthBalancer.redistribute(
        delta: 100, resizedIndex: 3, widths: widths, limits: playlistLike)
    #expect(result == [400, 196, 40, 64, 40])
    #expect(result.reduce(0, +) == widths.reduce(0, +))
}

@Test("PBT: сумма ширин не меняется, каждая колонка остаётся в своём коридоре")
func balancerProperties() async {
    let mins = Gen.int(in: 16...120).array(of: 2...9)
    let spans = Gen.int(in: 0...400).array(of: 2...9)
    let offsets = Gen.int(in: 0...400).array(of: 2...9)
    let elastic = Gen.bool().array(of: 2...9)
    await propertyCheck(input: mins, spans, offsets, elastic, Gen.int(in: -300...300), Gen.int(in: 0...8)) {
        mins, spans, offsets, elastic, delta, indexSeed in
        let count = min(min(mins.count, spans.count), min(offsets.count, elastic.count))
        guard count >= 2 else { return }
        let limits = (0..<count).map {
            ColumnWidthLimits(
                minWidth: CGFloat(mins[$0]),
                maxWidth: CGFloat(mins[$0] + spans[$0]),
                isElastic: elastic[$0])
        }
        let widths = (0..<count).map { index -> CGFloat in
            min(limits[index].minWidth + CGFloat(offsets[index]), limits[index].maxWidth)
        }
        let resizedIndex = indexSeed % count
        let result = ColumnWidthBalancer.redistribute(
            delta: CGFloat(delta), resizedIndex: resizedIndex, widths: widths, limits: limits)
        #expect(result.count == count)
        #expect(abs(result.reduce(0, +) - widths.reduce(0, +)) < 0.000_001)
        for index in 0..<count {
            #expect(result[index] >= limits[index].minWidth)
            #expect(result[index] <= limits[index].maxWidth)
        }
    }
}
