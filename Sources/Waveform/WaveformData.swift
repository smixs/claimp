import Foundation

/// Готовая волна трека: фиксированное число колонок, в каждой - энергия трёх полос.
public struct WaveformData: Sendable, Equatable {
    /// Столько колонок считаем на трек (алгоритм Mixxx, решение владельца 15.09.2026).
    public static let columnCount = 3840
    /// Версия бинарного формата кэша; меняется - старые файлы кэша перестают подходить.
    /// 3: в полосах `low`/`mid`/`high` лежит RMS полосы (600 Гц / 4 кГц), нормированный общим пиком.
    /// 2: те же полосы, но пик `max|x|` и своя нормировка у каждой полосы; 1: один общий пик на три полосы.
    public static let formatVersion: UInt32 = 3

    /// Сигнатура файла кэша.
    static let magic: [UInt8] = Array("DJWF".utf8)
    /// "DJWF" + версия + число колонок.
    static let headerSize = 12
    /// low, mid, high - по четыре байта.
    static let bytesPerColumn = 12

    public struct Column: Sendable, Equatable {
        public let low: Float
        public let mid: Float
        public let high: Float

        /// Высота столбика на экране: самая громкая из трёх полос.
        public var peak: Float { max(low, max(mid, high)) }

        public init(low: Float, mid: Float, high: Float) {
            self.low = low
            self.mid = mid
            self.high = high
        }
    }

    public let columns: [Column]

    public init(columns: [Column]) {
        self.columns = columns
    }

    /// Колонка под курсором: доля трека вне 0…1 прижимается к краям волны.
    public func column(atProgress progress: Double) -> Column? {
        guard !columns.isEmpty else { return nil }
        let clamped = min(max(progress, 0), 1)
        let index = Int(clamped * Double(columns.count - 1))
        return columns[index]
    }

    /// Бинарный формат кэша: "DJWF" | версия LE | число колонок LE | колонки по три Float32 LE.
    public func encoded() -> Data {
        var data = Data(capacity: Self.headerSize + columns.count * Self.bytesPerColumn)
        data.append(contentsOf: Self.magic)
        data.append(littleEndian: Self.formatVersion)
        data.append(littleEndian: UInt32(columns.count))
        for column in columns {
            data.append(littleEndian: column.low.bitPattern)
            data.append(littleEndian: column.mid.bitPattern)
            data.append(littleEndian: column.high.bitPattern)
        }
        return data
    }

    /// Разбор файла кэша. Любой чужой, обрезанный или испорченный буфер - `badCache`, не мусор.
    public static func decoded(from data: Data) throws -> WaveformData {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize, Array(bytes[0..<4]) == magic else { throw WaveformError.badCache }
        guard UInt32(littleEndianBytes: bytes, at: 4) == formatVersion else { throw WaveformError.badCache }
        let count = Int(UInt32(littleEndianBytes: bytes, at: 8))
        guard bytes.count == headerSize + count * bytesPerColumn else { throw WaveformError.badCache }
        var columns = [Column]()
        columns.reserveCapacity(count)
        for index in 0..<count {
            let offset = headerSize + index * bytesPerColumn
            columns.append(Column(
                low: Float(bitPattern: UInt32(littleEndianBytes: bytes, at: offset)),
                mid: Float(bitPattern: UInt32(littleEndianBytes: bytes, at: offset + 4)),
                high: Float(bitPattern: UInt32(littleEndianBytes: bytes, at: offset + 8))))
        }
        return WaveformData(columns: columns)
    }
}

public enum WaveformError: Error, Equatable {
    case cannotOpen(URL)
    /// Поток закончился досрочно: URL и фрейм, на котором оборвалось чтение.
    case cannotRead(URL, Int)
    case cancelled
    case badCache
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}

private extension UInt32 {
    init(littleEndianBytes bytes: [UInt8], at offset: Int) {
        self = UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
