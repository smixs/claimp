import AppKit
import Core

// Parts adapted from bocan/bocan-music (Apache-2.0): pasteboardWriter с парой
// (.string для внутреннего move, .fileURL наружу) и маска .copy для внешнего приёмника.

enum PlaylistColumn: String, CaseIterable {
    case played, number, title, artist, year, duration, bitrate, bpm, key

    /// Заголовки коротко: девять колонок должны влезать в минимальные 420 pt окна.
    var headerTitle: String {
        switch self {
        case .played: return Strings.Column.played
        case .number: return Strings.Column.number
        case .title: return Strings.Column.title
        case .artist: return Strings.Column.artist
        case .year: return Strings.Column.year
        case .duration: return Strings.Column.duration
        case .bitrate: return Strings.Column.bitrate
        case .bpm: return Strings.Column.bpm
        case .key: return Strings.Column.key
        }
    }

    /// Поле сортировки для клика по заголовку; nil - колонка не сортируется.
    var sortField: TrackSortField? {
        TrackSortField.forColumnKey(rawValue)
    }

    /// Стартовые ширины из SPEC §4.1 и общие границы ручного изменения.
    /// Ширина `Key` зависит от формата тональности из настроек: «8A · Am» длиннее «8A».
    @MainActor func applyWidth(to column: NSTableColumn, keyFormat: KeyFormat = .camelot) {
        column.width = startWidth(keyFormat: keyFormat)
        applyLimits(to: column)
    }

    /// Границы и способ изменения ширины. Решение владельца 2026-09-16: тянется любая колонка,
    /// в том числе числовая; содержимое, которое не влезло, обрезается, а строка не расширяется.
    /// Название и Исполнитель, кроме того, делят между собой лишнюю ширину окна.
    @MainActor func applyLimits(to column: NSTableColumn) {
        let range = widthRange(keyFormat: SettingsStore.shared.value.keyFormat)
        column.minWidth = Theme.column.scaled(range.lowerBound)
        column.maxWidth = Theme.column.scaled(range.upperBound)
        column.resizingMask = stretches
            ? [.userResizingMask, .autoresizingMask]
            : [.userResizingMask]
    }

    /// Коридор ручного изменения: у Названия и Исполнителя широкий, у числовых узкий -
    /// иначе одна цифра растягивается на пол-окна (отчёт research/07 §6.1).
    func widthRange(keyFormat: KeyFormat) -> ClosedRange<CGFloat> {
        switch self {
        case .played: return Theme.column.playedMin...Theme.column.playedMax
        case .number: return Theme.column.numberMin...Theme.column.numberMax
        case .title: return Theme.column.titleMin...Theme.column.titleMax
        case .artist: return Theme.column.artistMin...Theme.column.artistMax
        case .year: return Theme.column.yearMin...Theme.column.yearMax
        case .duration: return Theme.column.durationMin...Theme.column.durationMax
        case .bitrate: return Theme.column.bitrateMin...Theme.column.bitrateMax
        case .bpm: return Theme.column.bpmMin...Theme.column.bpmMax
        case .key:
            return keyFormat == .both
                ? Theme.column.keyBothMin...Theme.column.keyBothMax
                : Theme.column.keyMin...Theme.column.keyMax
        }
    }

    /// Ширина при первом показе: дальше её помнит autosave таблицы или рука владельца.
    @MainActor func startWidth(keyFormat: KeyFormat) -> CGFloat {
        switch self {
        case .played: return Theme.column.scaled(Theme.column.played)
        case .number: return Theme.column.scaled(Theme.column.number)
        case .title: return Theme.column.titleIdeal
        case .artist: return Theme.column.artistIdeal
        case .year: return Theme.column.scaled(Theme.column.year)
        case .duration: return Theme.column.scaled(Theme.column.duration)
        case .bitrate: return Theme.column.scaled(Theme.column.bitrate)
        case .bpm: return Theme.column.scaled(Theme.column.bpm)
        case .key: return Theme.column.scaled(keyFormat == .both ? Theme.column.keyBoth : Theme.column.key)
        }
    }

    /// Колонка забирает лишнюю ширину окна: текст растёт, цифры остаются как поставили.
    var stretches: Bool {
        self == .title || self == .artist
    }

    var alignsRight: Bool {
        switch self {
        case .number, .year, .duration, .bitrate, .bpm: return true
        case .played, .title, .artist, .key: return false
        }
    }
}

/// Выделение и «играющий трек» без системного синего рисуют сами ячейки.
/// (Делегатный rowViewForRow на macOS 26 с diffable-источником не вызывается -
/// таблица создаёт обычный NSTableRowView, проверено логом.)
@MainActor protocol RowTinting: AnyObject {
    func setSelected(_ selected: Bool)
    /// Строка звучащего трека: ярче обычного выделения и главнее его при совпадении.
    func setPlaying(_ playing: Bool)
}

/// Цвета строки: играющий трек главнее выделения мышью, выделение - главнее обычного фона.
/// Одно место на обе ячейки, чтобы «ярче» не разъехалось между колонками.
@MainActor enum RowTint {
    static func background(playing: Bool, selected: Bool) -> NSColor? {
        if playing { return Theme.row.playingBackground }
        return selected ? Theme.surface.raised : nil
    }

    static func text(playing: Bool, selected: Bool, base: NSColor) -> NSColor {
        if playing { return Theme.row.playingText }
        return selected ? Theme.accent.violet : base
    }
}

/// Кастомное выделение вместо системного синего (приём Aural).
/// На macOS 26 с diffable-источником таблица rowViewForRow не вызывает,
/// поэтому рабочее выделение рисуют ячейки; здесь - та же плоская заливка.
final class PlaylistRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        Theme.surface.raised.setFill()
        bounds.fill()
    }
}

/// Лампочка «сыграно»: плоский кружок. Горит - заливка accent.pink,
/// погашена - только контур accent.gray.
final class DotWell: NSView {
    var isOn = false {
        didSet { restyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        restyle()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        restyle()
    }

    private func restyle() {
        let radius = min(bounds.width, bounds.height) / 2
        Theme.fill(self, color: isOn ? Theme.accent.pink : nil, radius: radius)
        layer?.borderColor = Theme.accent.gray.cgColor
        layer?.borderWidth = isOn ? 0 : Theme.size.lampBorder
    }
}

/// Заголовки колонок: плоская полоса surface.raised, подпись 11 pt secondary,
/// шов border.subtle снизу, индикатор сортировки - треугольник accent.violet.
final class FlatHeaderCell: NSTableHeaderCell {
    /// Направление сортировки по этой колонке; nil - сортируют не по ней. Штатную отрисовку
    /// индикатора делает `NSTableHeaderCell.draw`, которую плоский заголовок не зовёт,
    /// поэтому треугольник рисуем сами - у правого края, как в Aural и Cog.
    var sortAscending: Bool?

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Theme.surface.raised.setFill()
        cellFrame.fill()
        Theme.border.subtle.setFill()
        NSRect(
            x: cellFrame.minX, y: cellFrame.maxY - Theme.size.hairline,
            width: cellFrame.width, height: Theme.size.hairline
        ).fill()
        // Вертикальная риска по левому краю: без неё границ колонок не видно и непонятно,
        // где хвататься (жалоба владельца 16.09, кадры frame-06/12). У первой видимой колонки
        // левый край - это край таблицы, там риска не нужна.
        if cellFrame.minX > 0 {
            let inset = Theme.column.headerTickInset
            NSRect(
                x: cellFrame.minX, y: cellFrame.minY + inset,
                width: Theme.size.hairline, height: max(0, cellFrame.height - 2 * inset)
            ).fill()
        }
        drawInterior(withFrame: cellFrame, in: controlView)
        if let ascending = sortAscending {
            drawSortIndicator(
                withFrame: cellFrame, in: controlView, ascending: ascending, priority: 0)
        }
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        let title = NSAttributedString(
            string: stringValue,
            attributes: [
                .font: Theme.font.columnHeader,
                .foregroundColor: Theme.text.secondary,
                .paragraphStyle: style,
            ]
        )
        let height = title.size().height
        // Треугольник сортировки рисуется в правом поле ячейки, поэтому места под него
        // отдельно не резервируем: подпись и так заканчивается за 8 pt до края.
        let inset = Theme.column.cellInsetLeading + Theme.column.cellInsetTrailing
        title.draw(in: NSRect(
            x: cellFrame.minX + Theme.column.cellInsetLeading, y: cellFrame.midY - height / 2,
            width: max(0, cellFrame.width - inset), height: height
        ))
    }

    override func drawSortIndicator(
        withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int
    ) {
        let side: CGFloat = Theme.spacing.s
        let box = NSRect(
            x: cellFrame.maxX - side, y: cellFrame.midY - side / 4,
            width: side, height: side / 2
        )
        let path = NSBezierPath()
        // Заголовок нарисован в перевёрнутых координатах: «по возрастанию» - остриё вниз.
        path.move(to: NSPoint(x: box.minX, y: ascending ? box.minY : box.maxY))
        path.line(to: NSPoint(x: box.maxX, y: ascending ? box.minY : box.maxY))
        path.line(to: NSPoint(x: box.midX, y: ascending ? box.maxY : box.minY))
        path.close()
        Theme.accent.violet.setFill()
        path.fill()
    }
}

/// Фон полосы заголовков за последней колонкой и широкая зона захвата разделителя.
final class FlatHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.surface.raised.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
    }

    /// Курсор ↔ появляется не по пикселю границы, а в зоне вокруг неё: свои ректы
    /// складываются с приватными ректами AppKit, конфликта нет (research/07 §3.4).
    override func resetCursorRects() {
        super.resetCursorRects()
        guard let table = tableView else { return }
        let zone = Theme.column.resizeHotZone
        for index in 0..<table.numberOfColumns where !table.tableColumns[index].isHidden {
            let rect = headerRect(ofColumn: index)
            guard rect.width > 0 else { continue }
            addCursorRect(
                NSRect(x: rect.maxX - zone, y: 0, width: 2 * zone, height: bounds.height),
                cursor: .resizeLeftRight)
        }
    }

    /// Ширины колонок поехали - зоны захвата пересчитываются под новые границы.
    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }
}

/// Прозрачная кнопка поверх лунки: только клик, рисует лунка.
final class PlayedDotButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        isTransparent = true
        title = ""
        imagePosition = .noImage
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
}

final class PlayedDotCell: NSTableCellView, RowTinting {
    static let identifier = NSUserInterfaceItemIdentifier("PlayedDotCell")
    let well = DotWell()
    let dot = PlayedDotButton()
    var onTap: (() -> Void)?
    private var isCellSelected = false
    private var isPlayingRow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        well.translatesAutoresizingMaskIntoConstraints = false
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.target = self
        dot.action = #selector(tapped)
        addSubview(well)
        addSubview(dot)
        NSLayoutConstraint.activate([
            well.centerXAnchor.constraint(equalTo: centerXAnchor),
            well.centerYAnchor.constraint(equalTo: centerYAnchor),
            well.widthAnchor.constraint(equalToConstant: Theme.size.lamp),
            well.heightAnchor.constraint(equalToConstant: Theme.size.lamp),
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor),
            dot.topAnchor.constraint(equalTo: topAnchor),
            dot.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc private func tapped() {
        onTap?()
    }

    func setLamp(on: Bool) {
        well.isOn = on
    }

    func setSelected(_ selected: Bool) {
        isCellSelected = selected
        restyle()
    }

    func setPlaying(_ playing: Bool) {
        isPlayingRow = playing
        restyle()
    }

    override func layout() {
        super.layout()
        restyle()
    }

    private func restyle() {
        Theme.fill(self, color: RowTint.background(playing: isPlayingRow, selected: isCellSelected))
    }
}

final class PlaylistTextCell: NSTableCellView, RowTinting {
    static let identifier = NSUserInterfaceItemIdentifier("PlaylistTextCell")
    let label = FadingLabel()
    var baseColor: NSColor = Theme.text.primary {
        didSet { restyle() }
    }
    private var isCellSelected = false
    private var isPlayingRow = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.column.cellInsetLeading),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.column.cellInsetTrailing),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setSelected(_ selected: Bool) {
        isCellSelected = selected
        restyle()
    }

    func setPlaying(_ playing: Bool) {
        isPlayingRow = playing
        restyle()
    }

    override func layout() {
        super.layout()
        restyle()
    }

    private func restyle() {
        let fill = RowTint.background(playing: isPlayingRow, selected: isCellSelected)
        label.textColor = RowTint.text(playing: isPlayingRow, selected: isCellSelected, base: baseColor)
        // Мягкая обрезка уходит в цвет самой строки, иначе край текста гаснет в чужой фон.
        label.fadeColor = fill ?? Theme.background.base
        Theme.fill(self, color: fill)
    }
}

final class PlaylistTableView: NSTableView {
    var onDeleteKey: (() -> Void)?
    var onSpaceKey: (() -> Void)?
    var onEnterKey: (() -> Void)?

    /// Правый клик по строке вне выделения переносит выделение на неё (стандартное поведение
    /// AppKit): меню всегда работает с тем, что владелец видит выделенным.
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return super.menu(for: event)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:
            if selectedRowIndexes.isEmpty {
                super.keyDown(with: event)
            } else {
                onDeleteKey?()
            }
        case 49:
            onSpaceKey?()
        case 36, 76:
            if selectedRow >= 0 {
                onEnterKey?()
            } else {
                super.keyDown(with: event)
            }
        default:
            super.keyDown(with: event)
        }
    }
}

/// Diffable-источник с одной секцией; идентификатор строки - URL трека.
/// Клик по заголовку приходит в @objc-метод объекта, который стоит dataSource таблицы,
/// а не делегата: реализация в контроллере не вызывается вовсе. Поэтому метод живёт здесь
/// и отдаёт работу через хук - как pasteboardWriterForRow.
final class PlaylistDataSource: NSTableViewDiffableDataSource<Int, URL> {
    var sortHandler: (([NSSortDescriptor]) -> Void)?
    var writerForRow: ((Int) -> NSPasteboardItem?)?
    var validateDropHandler: ((NSDraggingInfo, Int) -> NSDragOperation)?
    var acceptDropHandler: ((NSDraggingInfo, Int) -> Bool)?

    /// Таблица зовёт метод с главного потока; @MainActor нужен, чтобы читать sortDescriptors.
    @MainActor @objc func tableView(
        _ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
        sortHandler?(tableView.sortDescriptors)
    }

    @objc func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        writerForRow?(row)
    }

    @objc func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        validateDropHandler?(info, row) ?? []
    }

    @objc func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        acceptDropHandler?(info, row) ?? false
    }
}
