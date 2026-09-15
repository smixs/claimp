import Foundation
import Testing

@testable import Core

private func tempDB() throws -> (PlayedStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dbURL = dir.appendingPathComponent("player.sqlite")
    return (try PlayedStore(path: dbURL), dir)
}

@Test("Лампочка переживает закрытие и повторное открытие базы")
func playedSurvivesReopen() throws {
    let (store, dir) = try tempDB()
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = URL(fileURLWithPath: "/music/a.mp3")
    #expect(try store.isPlayed(url) == false)
    try store.setPlayed(url, true)
    #expect(try store.isPlayed(url) == true)

    let dbURL = dir.appendingPathComponent("player.sqlite")
    let reopened = try PlayedStore(path: dbURL)
    #expect(try reopened.isPlayed(url) == true)
    try reopened.setPlayed(url, false)
    #expect(try reopened.isPlayed(url) == false)
}

@Test("playedURLs возвращает только помеченные из списка")
func playedURLsFiltersMarked() throws {
    let (store, dir) = try tempDB()
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = (1...3).map { URL(fileURLWithPath: "/music/\($0).mp3") }
    try store.setPlayed(urls[0], true)
    try store.setPlayed(urls[2], true)
    #expect(try store.playedURLs(among: urls) == Set([urls[0], urls[2]]))
    // Снятая лампочка из запроса выпадает: строка в базе остаётся, но played = 0.
    try store.setPlayed(urls[0], false)
    #expect(try store.playedURLs(among: urls) == Set([urls[2]]))
    #expect(try store.playedURLs(among: []).isEmpty)
}

@Test("Снятая лампочка переживает переоткрытие базы и не возвращается в playedURLs")
func unplayedLightStaysOffAfterReopen() throws {
    let (store, dir) = try tempDB()
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = (1...3).map { URL(fileURLWithPath: "/music/\($0).mp3") }
    for url in urls { try store.setPlayed(url, true) }
    try store.setPlayed(urls[1], false)

    // §6.10: состояние лампочек переживает перезапуск - снятая не зажигается снова.
    let reopened = try PlayedStore(path: dir.appendingPathComponent("player.sqlite"))
    #expect(try reopened.playedURLs(among: urls) == Set([urls[0], urls[2]]))
    #expect(try reopened.isPlayed(urls[1]) == false)
}

@Test("Плейлист сохраняет порядок и текущий трек без дублей при перезаписи")
func playlistRoundtrip() throws {
    let (store, dir) = try tempDB()
    defer { try? FileManager.default.removeItem(at: dir) }
    let urls = (1...3).map { URL(fileURLWithPath: "/music/\($0).mp3") }
    #expect(try store.loadPlaylist() == .empty)

    try store.savePlaylist(urls, current: urls[1])
    var state = try store.loadPlaylist()
    #expect(state.urls == urls)
    #expect(state.current == urls[1])

    try store.savePlaylist(urls, current: nil)
    state = try store.loadPlaylist()
    #expect(state.urls == urls)
    #expect(state.current == nil)
    #expect(state.urls.count == 3)
}

@Test("Инит на недоступном пути бросает ошибку")
func initOnBadPathThrows() {
    let bad = URL(fileURLWithPath: "/nonexistent-claimp-\(UUID().uuidString)/player.sqlite")
    #expect(throws: (any Error).self) { try PlayedStore(path: bad) }
}
