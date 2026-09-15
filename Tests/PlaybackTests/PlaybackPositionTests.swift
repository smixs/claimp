import Foundation
import Testing

@testable import Playback

@Suite("PlaybackPosition")
struct PlaybackPositionTests {
    @Test("Доля 30/120 равна 0.25")
    func fractionOfQuarter() {
        #expect(PlaybackPosition(current: 30, total: 120).fraction == 0.25)
    }

    @Test("Нулевая и отрицательная длительность дают ровно 0, а не NaN")
    func fractionOfZeroTotalIsZero() {
        let zero = PlaybackPosition(current: 30, total: 0).fraction
        #expect(zero == 0)
        #expect(!zero.isNaN)
        #expect(PlaybackPosition(current: 30, total: -5).fraction == 0)
        #expect(PlaybackPosition(current: 0, total: 0).fraction == 0)
    }

    @Test("Доля не выходит за 0…1 и переживает мусор на входе")
    func fractionIsClamped() {
        #expect(PlaybackPosition(current: 200, total: 120).fraction == 1)
        #expect(PlaybackPosition(current: -3, total: 120).fraction == 0)
        #expect(PlaybackPosition(current: .nan, total: 120).fraction == 0)
        #expect(!PlaybackPosition(current: .infinity, total: 120).fraction.isNaN)
    }
}
