import MusicUnderstanding
import PropertyBased
import Testing

@testable import Analysis

/// Имена тоники, которые умеет сворачивать наша таблица.
private let ourTonicNames = Array(MusicalKey.appleTonicSemitones.keys).sorted()
private let modeNames = MusicalKey.Mode.allCases.map(\.rawValue)

@Test("Свёртка знает ровно те имена тоники, которые есть у фреймворка")
func tonicNamesMatchFramework() {
    // Семнадцать имён (энгармонические пары приходят обеими записями) - проверка от
    // самого фреймворка: появится новое имя, и тест покраснеет, а не отдаст пустую тональность.
    #expect(ourTonicNames.count == 17)
    for name in ourTonicNames {
        #expect(KeyResult.Tonic(rawValue: name) != nil, "фреймворк не знает имени \(name)")
    }
}

@Test("PBT: любое имя тоники Apple с любым ладом даёт валидный Camelot и roundtrip")
func appleNamesFoldIntoValidCamelot() async {
    // Генераторы дают индексы, а не элементы: Gen.element отдаёт Optional и прячет промах.
    await propertyCheck(
        input: Gen.int(in: 0..<ourTonicNames.count), Gen.int(in: 0..<modeNames.count)
    ) { nameIndex, modeIndex in
        let name = ourTonicNames[nameIndex]
        let modeName = modeNames[modeIndex]
        let key = try #require(MusicalKey(appleTonicName: name, modeName: modeName))
        let code = key.camelot
        let number = try #require(Int(code.dropLast()))
        #expect((1...12).contains(number))
        #expect(code.hasSuffix(modeName == "minor" ? "A" : "B"))
        // Код Camelot однозначен: разбор возвращает ту же тональность.
        #expect(MusicalKey(camelot: code) == key)
        #expect(key.shortName.hasSuffix("m") == (modeName == "minor"))
    }
}

@Test("Двенадцать классов на два лада дают двадцать четыре разных кода")
func twentyFourDistinctCodes() {
    let keys = MusicalKey.Tonic.allCases.flatMap { tonic in
        MusicalKey.Mode.allCases.map { MusicalKey(tonic: tonic, mode: $0) }
    }
    #expect(Set(keys.map(\.camelot)).count == 24)
    // Якоря круга: Am = 8A, C = 8B, F#m = 11A, Eb minor = 2A (сверено с research/06 §2.3).
    #expect(MusicalKey(tonic: .a, mode: .minor).camelot == "8A")
    #expect(MusicalKey(tonic: .c, mode: .major).camelot == "8B")
    #expect(MusicalKey(tonic: .fSharp, mode: .minor).camelot == "11A")
    #expect(MusicalKey(tonic: .dSharp, mode: .minor).camelot == "2A")
    #expect(MusicalKey(tonic: .a, mode: .minor).shortName == "Am")
    #expect(MusicalKey(tonic: .fSharp, mode: .minor).shortName == "F#m")
}

@Test("Незнакомое имя тоники и мусорный Camelot не сворачиваются молча")
func garbageNamesReturnNil() {
    #expect(MusicalKey(appleTonicName: "hSharp", modeName: "minor") == nil)
    #expect(MusicalKey(appleTonicName: "a", modeName: "dorian") == nil)
    #expect(MusicalKey(camelot: "13A") == nil)
    #expect(MusicalKey(camelot: "0A") == nil)
    #expect(MusicalKey(camelot: "8C") == nil)
    #expect(MusicalKey(camelot: "") == nil)
}

@Test("Нотная запись из тега разбирается обратно в тональность")
func shortNameRoundTrip() {
    for tonic in MusicalKey.Tonic.allCases {
        for mode in MusicalKey.Mode.allCases {
            let key = MusicalKey(tonic: tonic, mode: mode)
            #expect(MusicalKey(shortName: key.shortName) == key)
        }
    }
    // Бемоли пишут другие программы; энгармоника сворачивается в тот же класс.
    #expect(MusicalKey(shortName: "Bbm") == MusicalKey(tonic: .aSharp, mode: .minor))
    #expect(MusicalKey(shortName: " Ab ") == MusicalKey(tonic: .gSharp, mode: .major))
}

@Test("Тег понимается и как Camelot, и как нота; мусор - nil")
func tagKeyAcceptsBothNotations() {
    #expect(MusicalKey(tag: "8A") == MusicalKey(tonic: .a, mode: .minor))
    #expect(MusicalKey(tag: "Am") == MusicalKey(tonic: .a, mode: .minor))
    #expect(MusicalKey(tag: "F#m") == MusicalKey(tonic: .fSharp, mode: .minor))
    #expect(MusicalKey(tag: "C") == MusicalKey(tonic: .c, mode: .major))
    #expect(MusicalKey(shortName: "Hm") == nil)
    #expect(MusicalKey(shortName: "") == nil)
    #expect(MusicalKey(shortName: "C##") == nil)
    #expect(MusicalKey(tag: "not a key") == nil)
}
