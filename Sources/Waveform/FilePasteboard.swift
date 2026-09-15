import AppKit

/// Общий рецепт drag-out файла: `.fileURL` с абсолютным адресом - тот же, что у строки плейлиста
/// (`PlaylistController.pasteboardItem`), поэтому Finder, Ableton и Bitwig получают копию файла.
/// Своё место, а не волна: волна - только перемотка (решение владельца 15:36), помощник общий.
public enum FilePasteboard {
    nonisolated public static func pasteboardItem(for url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        return item
    }
}

extension WaveformView {
    /// Имя оставлено ради единственного вызова - обложки в шапке (`CoverView.mouseDragged`);
    /// рецепт живёт в `FilePasteboard`, новых потребителей у этого имени нет.
    nonisolated public static func pasteboardItem(for url: URL) -> NSPasteboardItem {
        FilePasteboard.pasteboardItem(for: url)
    }
}
