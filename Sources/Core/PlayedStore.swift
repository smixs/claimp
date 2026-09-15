import Foundation
import GRDB

public struct PlaylistState: Sendable, Equatable {
    public let urls: [URL]
    public let current: URL?
    public static let empty = PlaylistState(urls: [], current: nil)

    public init(urls: [URL], current: URL?) {
        self.urls = urls
        self.current = current
    }
}

public protocol PlayedStoring: Sendable {
    func isPlayed(_ url: URL) throws -> Bool
    func setPlayed(_ url: URL, _ value: Bool) throws
    /// Один запрос на весь плейлист.
    func playedURLs(among urls: [URL]) throws -> Set<URL>
    func savePlaylist(_ urls: [URL], current: URL?) throws
    func loadPlaylist() throws -> PlaylistState
}

/// Лампочки и порядок плейлиста в SQLite. Ключ лампочки - url.path
/// (решение владельца: хранится у файла по пути; переезд файла лампочку теряет).
/// DatabaseQueue потокобезопасен сам, методы синхронные и вызываются с любого актора.
public final class PlayedStore: PlayedStoring {
    private static let currentPathKey = "current_path"
    private let queue: DatabaseQueue

    /// Боевой путь: ~/Library/Application Support/Claimp/player.sqlite.
    public static func makeDefault() throws -> PlayedStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Claimp")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try PlayedStore(path: dir.appendingPathComponent("player.sqlite"))
    }

    /// Для тестов: любой путь, в т.ч. временная папка. Недоступный путь бросает ошибку.
    public init(path: URL) throws {
        var configuration = Configuration()
        configuration.journalMode = .wal
        let queue = try DatabaseQueue(path: path.path, configuration: configuration)
        try Self.migrate(queue)
        self.queue = queue
    }

    private static func migrate(_ queue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE played (
                    path TEXT PRIMARY KEY,
                    played INTEGER NOT NULL DEFAULT 0,
                    updated_at DOUBLE NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE playlist (
                    position INTEGER PRIMARY KEY,
                    path TEXT NOT NULL
                )
                """)
            try db.execute(sql: """
                CREATE TABLE app_state (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """)
        }
        try migrator.migrate(queue)
    }

    public func isPlayed(_ url: URL) throws -> Bool {
        try queue.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT played FROM played WHERE path = ?",
                arguments: [url.path]
            ) ?? false
        }
    }

    public func setPlayed(_ url: URL, _ value: Bool) throws {
        try queue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO played (path, played, updated_at) VALUES (?, ?, ?)",
                arguments: [url.path, value, Date().timeIntervalSince1970]
            )
        }
    }

    public func playedURLs(among urls: [URL]) throws -> Set<URL> {
        let wanted = Set(urls.map(\.path))
        guard !wanted.isEmpty else { return [] }
        let stored: Set<String> = try queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT path FROM played WHERE played <> 0"))
        }
        return Set(stored.intersection(wanted).map { URL(fileURLWithPath: $0) })
    }

    /// Пишет playlist и app_state в одной транзакции (queue.write транзакционен);
    /// DELETE перед вставкой не даёт дублей при повторном сохранении.
    public func savePlaylist(_ urls: [URL], current: URL?) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM playlist")
            for (position, url) in urls.enumerated() {
                try db.execute(
                    sql: "INSERT INTO playlist (position, path) VALUES (?, ?)",
                    arguments: [position, url.path]
                )
            }
            if let current {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO app_state (key, value) VALUES (?, ?)",
                    arguments: [Self.currentPathKey, current.path]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM app_state WHERE key = ?",
                    arguments: [Self.currentPathKey]
                )
            }
        }
    }

    /// Оба чтения - в одном queue.read: savePlaylist пишет обе таблицы одной транзакцией,
    /// незачем читать их двумя.
    public func loadPlaylist() throws -> PlaylistState {
        let (paths, current): ([String], String?) = try queue.read { db in
            let paths = try String.fetchAll(db, sql: "SELECT path FROM playlist ORDER BY position")
            let current = try String.fetchOne(
                db,
                sql: "SELECT value FROM app_state WHERE key = ?",
                arguments: [Self.currentPathKey]
            )
            return (paths, current)
        }
        return PlaylistState(
            urls: paths.map { URL(fileURLWithPath: $0) },
            current: current.map { URL(fileURLWithPath: $0) }
        )
    }
}
