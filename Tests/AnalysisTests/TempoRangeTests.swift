import Foundation
import PropertyBased
import Testing

@testable import Analysis

@Test("PBT: любой темп приводится внутрь диапазона и отличается только степенью двойки")
func normalizedStaysInRangeAndKeepsSignificand() async {
    let range = TempoRange.default
    await propertyCheck(input: Gen.double(in: 0.001...100_000)) { bpm in
        let result = try #require(range.normalized(bpm))
        #expect(result >= range.lower)
        #expect(result < range.upper)
        // Умножение и деление на два меняют только показатель степени: мантисса обязана совпасть.
        #expect(result.significand == bpm.significand)
    }
}

@Test("Октава темпа: половинный ответ фреймворка поднимается, двойной опускается")
func halvedAndDoubledTemposCollapseToRange() {
    let range = TempoRange.default
    #expect(range.normalized(85) == 170)
    #expect(range.normalized(87.5) == 175)
    #expect(range.normalized(172) == 172)
    #expect(range.normalized(360) == 90)
    #expect(range.normalized(45) == 90)
    #expect(range.lower == 90)
    #expect(range.upper == 180)
}

@Test("Не темп - не значение: ноль, отрицательное, NaN и бесконечность дают nil")
func garbageTempoIsNil() {
    let range = TempoRange.default
    #expect(range.normalized(0) == nil)
    #expect(range.normalized(-174) == nil)
    #expect(range.normalized(.nan) == nil)
    #expect(range.normalized(.infinity) == nil)
}
