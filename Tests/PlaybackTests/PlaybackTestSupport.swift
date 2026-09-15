import Foundation

@testable import Playback

/// Собирает поток `positions` в массив: тест читает последнюю позицию без гонки с тикером.
actor PositionLog {
    private var values: [PlaybackPosition] = []

    func append(_ position: PlaybackPosition) {
        values.append(position)
    }

    func last() -> PlaybackPosition? {
        values.last
    }

    func count() -> Int {
        values.count
    }
}

/// Подписчик на `PlayerEngine.positions`, живущий до конца теста.
@MainActor
final class PositionObserver {
    private let log: PositionLog
    private let task: Task<Void, Never>

    init(_ engine: PlayerEngine) {
        let log = PositionLog()
        self.log = log
        let stream = engine.positions
        task = Task { @MainActor in
            for await position in stream {
                await log.append(position)
            }
        }
    }

    func last() async -> PlaybackPosition? {
        await log.last()
    }

    func count() async -> Int {
        await log.count()
    }

    func stop() {
        task.cancel()
    }
}

/// Счётчик для колбэков движка: локальную `var` в escaping-замыкание не отдать.
@MainActor
final class Counter {
    var value = 0
}

/// Ошибки, доехавшие до `onError`.
@MainActor
final class ErrorLog {
    var errors: [PlayerEngineError] = []
}

/// URL, который увидел колбэк движка.
@MainActor
final class URLBox {
    var value: URL?
}

/// Ждёт выполнения условия, но не дольше `timeout`. `false` - не дождались.
@MainActor
func waitUntil(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        do {
            try await Task.sleep(for: .milliseconds(20))
        } catch {
            return false
        }
    }
    return await condition()
}

/// Сравнение долей с допуском: позиция тикает, точного равенства ждать неоткуда.
func isClose(_ value: Double?, _ expected: Double, tolerance: Double = 0.01) -> Bool {
    guard let value else { return false }
    return abs(value - expected) <= tolerance
}
