import Foundation

/// Результат анализа одного трека.
public struct TrackAnalysis: Sendable, Equatable {
    /// Темп, уже приведённый к рабочему диапазону (`TempoRange`). nil - анализ темпа не дал.
    public var bpm: Double?
    /// Тональность; nil - анализ тональности не дал.
    public var key: MusicalKey?
    /// Доли в секундах от начала трека. Считается заодно с темпом, в интерфейсе пока не
    /// показывается - лежит здесь для будущей сетки на волне, в кэш не пишется.
    public var beats: [Double]
    public var analyzedAt: Date

    public init(bpm: Double?, key: MusicalKey?, beats: [Double], analyzedAt: Date) {
        self.bpm = bpm
        self.key = key
        self.beats = beats
        self.analyzedAt = analyzedAt
    }
}

/// Чем закончился разбор трека. Пропуск длинного микса - отдельный случай с причиной,
/// а не пустой результат: иначе в интерфейсе «не посчиталось» неотличимо от «не стали считать».
public enum AnalysisOutcome: Sendable, Equatable {
    case analyzed(TrackAnalysis)
    /// Трек длиннее порога: `TrackAnalyzer.maxDuration`.
    case skippedTooLong(duration: TimeInterval)
}
