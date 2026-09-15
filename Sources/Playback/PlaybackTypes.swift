import Foundation

/// Позиция в треке: снимок для курсора на волне.
public struct PlaybackPosition: Sendable, Equatable {
    /// Сколько уже проиграно, секунды.
    public let current: TimeInterval
    /// Длительность трека, секунды. 0 - длительность неизвестна.
    public let total: TimeInterval

    public init(current: TimeInterval, total: TimeInterval) {
        self.current = current
        self.total = total
    }

    /// Доля проигранного, 0…1.
    ///
    /// При `total <= 0` возвращает ровно 0: наружу не должен уехать ни NaN, ни Infinity.
    public var fraction: Double {
        guard total > 0, current.isFinite else { return 0 }
        return min(max(current / total, 0), 1)
    }
}

/// Состояние транспорта: `idle` - трек не загружен, `paused` - загружен и не играет.
public enum PlaybackState: Sendable, Equatable {
    case idle
    case playing
    case paused
}
