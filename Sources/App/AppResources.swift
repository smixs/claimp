import Foundation

/// Ресурсы таргета App. Штатный SwiftPM-аксессор ресурсов модуля (`.module` у класса
/// `Bundle`) ищет `Claimp_App.bundle` рядом с самим `.app` или по абсолютному пути каталога
/// сборки, поэтому в установленном приложении (например, `/Applications/Claimp.app`) он
/// падает fatalError - на этом уехал релиз 0.1.0. `scripts/build-app.sh` кладёт бандл в
/// `Contents/Resources`, там его и ищем; при запуске из `swift build` бандл лежит рядом с
/// исполняемым файлом. Обе точки проверяются явно, аксессор модуля не используется -
/// это стережёт шаг `make verify`.
enum AppResources {
    static let bundleName = "Claimp_App.bundle"

    /// Fail fast: нет бандла ни в одном из двух известных мест - ошибка упаковки.
    static func url(forResource name: String, withExtension ext: String) -> URL {
        let main = Bundle.main
        let candidates = [main.resourceURL, main.bundleURL, main.executableURL?.deletingLastPathComponent()]
            .compactMap { $0 }
            .map { $0.appendingPathComponent(bundleName) }
        for candidate in candidates {
            if let bundle = Bundle(url: candidate),
               let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        fatalError("\(name).\(ext) not found: no \(bundleName) in \(candidates.map(\.path))")
    }
}
