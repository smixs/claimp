import Testing

@testable import Core

@Test("Год из четырёх форматов строки даты тега")
func yearFromTagDateFormats() {
    #expect(YearParser.year(from: "1994") == 1994)
    #expect(YearParser.year(from: "1994-03-15") == 1994)
    #expect(YearParser.year(from: "15/03/1994") == 1994)
    #expect(YearParser.year(from: "1994.03") == 1994)
}

@Test("Мусор, nil и TDAT-ловушка дают nil")
func yearFromGarbageIsNil() {
    #expect(YearParser.year(from: nil) == nil)
    #expect(YearParser.year(from: "") == nil)
    #expect(YearParser.year(from: "hello") == nil)
    #expect(YearParser.year(from: "1503") == nil)
    #expect(YearParser.year(from: "1899") == nil)
    #expect(YearParser.year(from: "2100") == nil)
    #expect(YearParser.year(from: "199") == nil)
    #expect(YearParser.year(from: "19945") == nil)
    #expect(YearParser.year(from: "abc1994") == nil)
    #expect(YearParser.year(from: "1994a") == nil)
}

@Test("Берётся первое вхождение года в строке")
func yearTakesFirstOccurrence() {
    #expect(YearParser.year(from: "take 2001!") == 2001)
    #expect(YearParser.year(from: "15/03/1994 extra 2001") == 1994)
}
