import Testing
import PropertyBased

@testable import Core

// Требует зависимость CoreTests -> PropertyBased в Package.swift (владелец - скелетчик T0).

@Test("PBT: год из любого формата строки тега возвращается ровно")
func yearParserFindsEmbeddedYear() async {
    await propertyCheck(input: Gen.int(in: 1900...2099), Gen.int(in: 0...3)) { year, format in
        let raw: String
        switch format {
        case 0: raw = "\(year)"
        case 1: raw = "\(year)-03-15"
        case 2: raw = "15/03/\(year)"
        default: raw = "\(year).03"
        }
        #expect(YearParser.year(from: raw) == year)
    }
}

@Test("PBT: на произвольной строке не падает, вне 1900...2099 не возвращает")
func yearParserNeverCrashesOnGarbage() async {
    await propertyCheck(input: Gen.character(in: " "..."~").string(of: 0...64)) { raw in
        let result = YearParser.year(from: raw)
        if let result {
            #expect((1900...2099).contains(result))
        }
    }
}
