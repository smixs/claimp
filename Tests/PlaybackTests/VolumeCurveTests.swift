import Foundation
import PropertyBased
import Testing

@testable import Playback

@Suite("VolumeCurve")
struct VolumeCurveTests {
    /// Шкала фиксирована: -60 dB на нижнем конце хода, 0 dB на верхнем, порог тишины 0.02.
    @Test("Концы хода точные: 0 - тишина, 1 - полный сигнал")
    func endsAreExact() {
        #expect(VolumeCurve.gain(forPosition: 0) == 0)
        #expect(VolumeCurve.gain(forPosition: 1) == 1)
        #expect(VolumeCurve.position(forGain: 0) == 0)
        #expect(VolumeCurve.position(forGain: 1) == 1)
    }

    @Test("Середина хода даёт -30 dB ≈ 0.0316, а не половину амплитуды")
    func middleIsMinusThirtyDecibels() {
        let gain = VolumeCurve.gain(forPosition: 0.5)
        #expect(abs(Double(gain) - 0.0316227766) < 0.0001)
        // Смысл кривой: на середине фейдера сигнал далеко не половинный.
        #expect(gain < 0.05)
    }

    @Test("Ниже порога 0.02 фейдер закрыт ровно, на пороге уже звучит")
    func belowThresholdIsSilent() {
        #expect(VolumeCurve.gain(forPosition: 0.019) == 0)
        #expect(VolumeCurve.gain(forPosition: 0.01) == 0)
        #expect(VolumeCurve.gain(forPosition: VolumeCurve.silenceThreshold) > 0)
    }

    @Test("Вход вне 0…1 и мусор клампятся, а не уезжают наружу")
    func inputOutsideRangeIsClamped() {
        #expect(VolumeCurve.gain(forPosition: -0.5) == 0)
        #expect(VolumeCurve.gain(forPosition: 3) == 1)
        #expect(VolumeCurve.gain(forPosition: .nan) == 0)
        #expect(VolumeCurve.position(forGain: -1) == 0)
        #expect(VolumeCurve.position(forGain: 7) == 1)
        #expect(VolumeCurve.position(forGain: .nan) == 0)
    }

    @Test("PBT: позиция выше порога переживает round-trip через усиление")
    func roundTripAboveThreshold() async {
        await propertyCheck(input: Gen.double(in: VolumeCurve.silenceThreshold...1)) { position in
            let restored = VolumeCurve.position(forGain: VolumeCurve.gain(forPosition: position))
            // Допуск - точность Float у усиления: gain отдаётся движку в Float.
            #expect(abs(restored - position) < 0.001)
        }
    }

    @Test("PBT: кривая монотонна и не выходит за 0…1 на любом входе")
    func monotonicAndBounded() async {
        await propertyCheck(input: Gen.double(in: -2...3), Gen.double(in: 0...1)) { position, step in
            let lower = VolumeCurve.gain(forPosition: position)
            let higher = VolumeCurve.gain(forPosition: position + step)
            #expect(lower <= higher)
            #expect(lower >= 0 && lower <= 1)
            #expect(higher >= 0 && higher <= 1)
            #expect(!lower.isNaN && !higher.isNaN)
        }
    }
}
