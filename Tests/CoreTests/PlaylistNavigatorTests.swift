import Foundation
import PropertyBased
import Testing

@testable import Core

private let a = URL(fileURLWithPath: "/music/a.mp3")
private let b = URL(fileURLWithPath: "/music/b.mp3")
private let c = URL(fileURLWithPath: "/music/c.mp3")
private let gone = URL(fileURLWithPath: "/music/gone.mp3")

@Test("Следующий и предыдущий в середине списка")
func navigatorMiddle() {
    let urls = [a, b, c]
    #expect(PlaylistNavigator.next(after: a, in: urls) == b)
    #expect(PlaylistNavigator.next(after: b, in: urls) == c)
    #expect(PlaylistNavigator.previous(before: c, in: urls) == b)
    #expect(PlaylistNavigator.previous(before: b, in: urls) == a)
}

@Test("Края списка: последний даёт nil, первый даёт nil, неизвестный - первый/последний")
func navigatorEdges() {
    let urls = [a, b, c]
    #expect(PlaylistNavigator.next(after: c, in: urls) == nil)
    #expect(PlaylistNavigator.previous(before: a, in: urls) == nil)
    #expect(PlaylistNavigator.next(after: gone, in: urls) == a)
    #expect(PlaylistNavigator.previous(before: gone, in: urls) == c)
    #expect(PlaylistNavigator.next(after: nil, in: urls) == a)
    #expect(PlaylistNavigator.next(after: a, in: []) == nil)
}

@Test("Без воспроизведения шапка и волна показывают выделенную строку")
func shownTrackWithoutPlaybackIsSelection() {
    #expect(PlaylistNavigator.shown(playing: nil, selected: b) == b)
    #expect(PlaylistNavigator.shown(playing: nil, selected: nil) == nil)
}

@Test("При воспроизведении выделение не перебивает звучащий трек: шапка и волна идут за движком")
func shownTrackWhilePlayingIgnoresSelection() {
    #expect(PlaylistNavigator.shown(playing: a, selected: b) == a)
    #expect(PlaylistNavigator.shown(playing: a, selected: nil) == a)
    // Выделен тот же трек, что играет - он же и показан.
    #expect(PlaylistNavigator.shown(playing: c, selected: c) == c)
}

@Test("Восстановление: все файлы на месте - как было")
func restoreAllPresent() {
    let restored = PlaylistNavigator.restore(urls: [a, b], current: b, isExisting: { _ in true })
    #expect(restored.urls == [a, b])
    #expect(restored.current == b)
}

@Test("Восстановление: отсутствующий файл выбрасывается, потерянный текущий - nil")
func restoreDropsMissing() {
    let existing: Set<URL> = [a, c]
    let restored = PlaylistNavigator.restore(urls: [a, b, c], current: b, isExisting: existing.contains)
    #expect(restored.urls == [a, c])
    #expect(restored.current == nil)

    let kept = PlaylistNavigator.restore(urls: [a, b, c], current: c, isExisting: existing.contains)
    #expect(kept.urls == [a, c])
    #expect(kept.current == c)
}

/// Сидированный генератор (SplitMix64): случайный выбор проверяется значением, а не «похоже на случай».
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Test("Random с сидированным генератором даёт воспроизводимый трек из списка")
func randomIsDeterministicForSeed() {
    let urls = [a, b, c]
    var first = SeededGenerator(seed: 42)
    var second = SeededGenerator(seed: 42)
    let picked = PlaylistNavigator.random(excluding: a, in: urls, using: &first)
    #expect(picked == PlaylistNavigator.random(excluding: a, in: urls, using: &second))
    #expect(picked == b || picked == c)
}

@Test("Random: один трек даёт себя, пустой список - nil")
func randomEdges() {
    var generator = SeededGenerator(seed: 7)
    #expect(PlaylistNavigator.random(excluding: a, in: [a], using: &generator) == a)
    #expect(PlaylistNavigator.random(excluding: a, in: [], using: &generator) == nil)
    #expect(PlaylistNavigator.random(excluding: nil, in: [a], using: &generator) == a)
}

@Test("PBT: при двух и более треках случайный следующий никогда не равен текущему")
func randomNeverRepeatsCurrent() async {
    await propertyCheck(input: Gen.int(in: 1...50), Gen.int(in: 0...49), Gen.uint64()) { count, rawIndex, seed in
        let urls = (0..<count).map { URL(fileURLWithPath: "/pbt/\($0).mp3") }
        let current = urls[rawIndex % count]
        var generator = SeededGenerator(seed: seed)
        let picked = PlaylistNavigator.random(excluding: current, in: urls, using: &generator)
        #expect(picked != nil)
        #expect(urls.contains(picked!))
        if count > 1 {
            #expect(picked != current)
        } else {
            #expect(picked == current)
        }
    }
}
