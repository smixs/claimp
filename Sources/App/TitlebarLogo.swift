import AppKit

/// Логотип Claimp сверху окна вместо текстового заголовка (решение владельца 14:2x).
/// Титлбар прозрачный и content view занимает его высоту, поэтому логотип - обычная вьюха
/// в левом верхнем углу правее светофоров; сами кнопки окна остаются на своих местах.
/// Цвета файла не трогаем: NSImageView рисует SVG как есть.
@MainActor
enum TitlebarLogo {
    /// Fail fast: логотипа нет в бандле - ошибка сборки, а не повод рисовать текст.
    static func makeView() -> NSImageView {
        let url = AppResources.url(forResource: "claimp-logo", withExtension: "svg")
        guard let image = NSImage(contentsOf: url), image.size.height > 0 else {
            fatalError("claimp-logo.svg не читается как изображение: \(url.path)")
        }
        let logo = NSImageView(image: image)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.wantsLayer = true
        // Ширина - строго по пропорциям файла, ничего не обрезаем: при фиксированной ширине
        // логотип резался справа (правка владельца).
        logo.layer?.masksToBounds = false
        NSLayoutConstraint.activate([
            logo.heightAnchor.constraint(equalToConstant: Theme.size.logoHeight),
            logo.widthAnchor.constraint(
                equalTo: logo.heightAnchor,
                multiplier: image.size.width / image.size.height),
        ])
        return logo
    }
}
