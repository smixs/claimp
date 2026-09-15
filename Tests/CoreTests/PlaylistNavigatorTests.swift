import Foundation
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
