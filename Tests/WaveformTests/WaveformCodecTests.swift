import Foundation
import PropertyBased
import Testing

@testable import Waveform

private func waveform(from values: [Float]) -> WaveformData {
    WaveformData(columns: stride(from: 0, to: values.count, by: 3).map {
        WaveformData.Column(low: values[$0], mid: values[$0 + 1], high: values[$0 + 2])
    })
}

@Test("Кодек кэша: что записали, то и прочитали, бит в бит")
func codecRoundtrip() async {
    let columns = Gen.float(in: 0...1).array(of: WaveformData.columnCount * 3)
    await propertyCheck(count: 20, input: columns) { values in
        let original = waveform(from: values)
        try #expect( WaveformData.decoded(from: original.encoded()) == original)
    }
}

@Test("Кодек кэша: чужой буфер даёт badCache, а не мусор и не крэш")
func codecRejectsGarbage() async {
    // Произвольный мусор обязан отвергаться, а не декодироваться молча.
    await propertyCheck(count: 200, input: Gen.uint8().array(of: 0...512)) { bytes in
        #expect(throws: WaveformError.badCache) { try WaveformData.decoded(from: Data(bytes)) }
    }
    // Валидный буфер с одним испорченным байтом заголовка (offset 0…7).
    // Байт гарантированно меняется (&+ 1), иначе буфер остался бы валидным.
    let valid = Data(waveform(from: [Float](repeating: 0.5, count: WaveformData.columnCount * 3)).encoded())
    await propertyCheck(input: Gen.int(in: 0...7)) { offset in
        var bytes = [UInt8](valid)
        bytes[offset] = bytes[offset] &+ 1
        #expect(throws: WaveformError.badCache) { try WaveformData.decoded(from: Data(bytes)) }
    }
}

@Test("Кодек кэша: обрезанный валидный буфер даёт badCache")
func codecRejectsTruncated() throws {
    let valid = waveform(from: [Float](repeating: 0.5, count: WaveformData.columnCount * 3)).encoded()
    let half = valid.prefix(valid.count / 2)

    #expect(throws: WaveformError.badCache) { try WaveformData.decoded(from: half) }
}
