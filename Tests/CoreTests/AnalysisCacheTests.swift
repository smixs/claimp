import Foundation
import GRDB
import Testing

@testable import Core

private func tempDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// База версии v1 - такая, какая уже лежит у владельца: две таблицы, лампочка внутри,
/// про анализ она ничего не знает.
private func writeLegacyDatabase(at path: URL, playedPath: String) throws {
    let queue = try DatabaseQueue(path: path.path)
    try queue.write { db in
        try db.execute(sql: """
            CREATE TABLE played (path TEXT PRIMARY KEY, played INTEGER NOT NULL DEFAULT 0, updated_at DOUBLE NOT NULL)
            """)
        try db.execute(sql: "CREATE TABLE playlist (position INTEGER PRIMARY KEY, path TEXT NOT NULL)")
        try db.execute(sql: "CREATE TABLE app_state (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
        try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v1')")
        try db.execute(
            sql: "INSERT INTO played (path, played, updated_at) VALUES (?, 1, 0)",
            arguments: [playedPath])
    }
}

@Test("Миграция v2: старая база получает кэш анализа и не теряет лампочки")
func migrationV2KeepsOldDataAndAddsAnalysis() throws {
    let dir = try tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("player.sqlite")
    let url = URL(fileURLWithPath: "/music/legacy.mp3")
    try writeLegacyDatabase(at: path, playedPath: url.path)

    let store = try PlayedStore(path: path)
    #expect(try store.isPlayed(url) == true)
    let stamp = FileStamp(size: 100, mtime: 1)
    #expect(try store.analysis(for: url, stamp: stamp) == nil)
    try store.saveAnalysis(
        AnalysisRecord(bpm: 174, key: "8A", analyzedAt: Date(timeIntervalSince1970: 1_000)),
        for: url, stamp: stamp)
    #expect(try store.analysis(for: url, stamp: stamp)?.bpm == 174)
}

@Test("Кэш разбора переживает перезапуск, а после правки файла не подходит")
func analysisRoundtripAndStampMismatch() throws {
    let dir = try tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("player.sqlite")
    let url = URL(fileURLWithPath: "/music/track.mp3")
    let stamp = FileStamp(size: 7_340_032, mtime: 1_757_000_000.5)
    let record = AnalysisRecord(bpm: 174, key: "8A", analyzedAt: Date(timeIntervalSince1970: 1_757_000_100))

    let store = try PlayedStore(path: path)
    try store.saveAnalysis(record, for: url, stamp: stamp)

    let reopened = try PlayedStore(path: path)
    let loaded = try #require(try reopened.analysis(for: url, stamp: stamp))
    #expect(loaded == record)

    // Файл переписали: размер другой - старый разбор не отдаётся, трек посчитается заново.
    #expect(try reopened.analysis(for: url, stamp: FileStamp(size: 7_340_033, mtime: stamp.mtime)) == nil)
    #expect(try reopened.analysis(for: url, stamp: FileStamp(size: stamp.size, mtime: 0)) == nil)
    // Пустой разбор (темп не определился) тоже кэшируется: второй раз не считаем.
    let empty = AnalysisRecord(bpm: nil, key: nil, analyzedAt: Date(timeIntervalSince1970: 2))
    try reopened.saveAnalysis(empty, for: url, stamp: stamp)
    #expect(try reopened.analysis(for: url, stamp: stamp) == empty)
}

@Test("Отпечаток файла читается с диска, пропавший файл - ошибка, а не пустой отпечаток")
func fileStampReadsDiskAndFailsLoudly() throws {
    let dir = try tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let file = dir.appendingPathComponent("a.bin")
    try Data(repeating: 7, count: 1234).write(to: file)
    let stamp = try FileStamp.of(url: file)
    #expect(stamp.size == 1234)
    #expect(stamp.mtime > 0)
    #expect(throws: (any Error).self) { try FileStamp.of(url: dir.appendingPathComponent("нет.bin")) }
}

@Test("Приоритет: тег важнее анализа, пустое поле заполняет анализ")
func tagWinsOverAnalysis() {
    #expect(Track.resolvedBPM(tag: 174, analyzed: 87) == 174)
    #expect(Track.resolvedBPM(tag: nil, analyzed: 87) == 87)
    #expect(Track.resolvedBPM(tag: nil, analyzed: nil) == nil)
    #expect(Track.resolvedKey(tag: "Am", analyzed: "8A") == "Am")
    #expect(Track.resolvedKey(tag: nil, analyzed: "8A") == "8A")

    let tagged = sampleTrack(bpm: 174, key: "Am")
    let updated = tagged.withAnalysis(bpm: 87, key: "5A")
    #expect(updated.bpm == 174)
    #expect(updated.key == "Am")

    let bare = sampleTrack(bpm: nil, key: nil).withAnalysis(bpm: 174, key: "8A")
    #expect(bare.bpm == 174)
    #expect(bare.displayBPM == "174")
    #expect(bare.displayKey == "8A")
}

private func sampleTrack(bpm: Double?, key: String?) -> Track {
    Track(
        url: URL(fileURLWithPath: "/music/track.mp3"), title: "T", artist: "A", album: "",
        year: nil, duration: 200, bitrate: 320, bpm: bpm, key: key, sampleRate: 44_100,
        format: "MP3", artwork: nil, isPlayed: false)
}
