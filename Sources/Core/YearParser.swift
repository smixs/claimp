import Foundation

/// Год из произвольной строки даты тега: "1994", "1994-03-15", "15/03/1994", "1994.03".
/// Первое вхождение 19xx/20xx с границами слова (как \b(19|20)\d{2}\b у Petrichor).
/// Мусор и nil дают nil - поэтому "1503" из TDAT годом не становится.
public enum YearParser {
    /// Компилируется один раз; try! безопасен: паттерн - литерал, покрыт тестами.
    private static let pattern = try! NSRegularExpression(pattern: #"\b(19|20)\d{2}\b"#)

    public static func year(from raw: String?) -> Int? {
        guard let raw else { return nil }
        let range = NSRange(raw.startIndex..., in: raw)
        // Диапазон 1900...2099 держит сам паттерн: отдельная проверка после матча недостижима.
        guard let match = pattern.firstMatch(in: raw, range: range),
              let matchRange = Range(match.range, in: raw),
              let year = Int(raw[matchRange])
        else { return nil }
        return year
    }
}
