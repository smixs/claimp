import AppKit
import Core

// Parts adapted from bocan/bocan-music (Apache-2.0): pasteboardWriter с парой
// (.string для внутреннего move, .fileURL наружу) и маска .copy для внешнего приёмника.

enum PlaylistColumn: String, CaseIterable {
    case played, number, title, artist, year, duration

    var headerTitle: String {
        switch self {
        case .played: return "●"
        case .number: return "#"
        case .title: return "Название"
        case .artist: return "Исполнитель"
        case .year: return "Год"
        case .duration: return "Длит."
        }
    }

    var sortField: TrackSortField {
        TrackSortField(rawValue: rawValue) ?? .number
    }

    /// Фиксированные ширины из SPEC §4.1; текстовые колонки растут.
    @MainActor func applyWidth(to column: NSTableColumn) {
        switch self {
        case .played:
            fix(column, Theme.column.played)
        case .number:
            fix(column, Theme.column.number)
        case .title:
            column.width = Theme.column.titleIdeal
            column.minWidth = Theme.column.titleMin
            column.maxWidth = Theme.column.titleMax
            column.resizingMask = [.userResizingMask, .autoresizingMask]
        case .artist:
            column.width = Theme.column.artistIdeal
            column.minWidth = Theme.column.artistMin
            column.maxWidth = Theme.column.artistMax
            column.resizingMask = [.userResizingMask, .autoresizingMask]
        case .year:
            fix(column, Theme.column.year)
        case .duration:
            fix(column, Theme.column.duration)
        }
    }

    var alignsRight: Bool {
        self == .number || self == .year || self == .duration
    }

    @MainActor private func fix(_ column: NSTableColumn, _ width: CGFloat) {
        column.width = width
        column.minWidth = width
        column.maxWidth = width
        column.resizingMask = []
    }
}

/// Выделение без системного синего рисуют ячейки (вдавленная поверхность).
/// (Делегатный rowViewForRow на macOS 26 с diffable-источником не вызывается -
/// таблица создаёт обычный NSTableRowView, проверено логом.)
@MainActor protocol SelectionTinting: AnyObject {
    func setSelected(_ selected: Bool)
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
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Theme.surface.raised.setFill()
        cellFrame.fill()
        Theme.border.subtle.setFill()
        NSRect(
            x: cellFrame.minX, y: cellFrame.maxY - Theme.size.hairline,
            width: cellFrame.width, height: Theme.size.hairline
        ).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
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
        title.draw(in: NSRect(
            x: cellFrame.minX + Theme.spacing.xs, y: cellFrame.midY - height / 2,
            width: max(0, cellFrame.width - Theme.spacing.s), height: height
        ))
    }

    override func drawSortIndicator(
        withFrame cellFrame: NSRect, in controlView: NSView, ascending: Bool, priority: Int
    ) {
        let side: CGFloat = Theme.spacing.s
        let box = NSRect(
            x: cellFrame.midX - side / 2, y: cellFrame.midY - side / 4,
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

/// Фон полосы заголовков за последней колонкой.
final class FlatHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        Theme.surface.raised.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
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

final class PlayedDotCell: NSTableCellView, SelectionTinting {
    static let identifier = NSUserInterfaceItemIdentifier("PlayedDotCell")
    let well = DotWell()
    let dot = PlayedDotButton()
    var onTap: (() -> Void)?
    private var isCellSelected = false

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
        Theme.fill(self, color: selected ? Theme.surface.raised : nil)
    }

    override func layout() {
        super.layout()
        Theme.fill(self, color: isCellSelected ? Theme.surface.raised : nil)
    }
}

final class PlaylistTextCell: NSTableCellView, SelectionTinting {
    static let identifier = NSUserInterfaceItemIdentifier("PlaylistTextCell")
    let label = FadingLabel()
    var baseColor: NSColor = Theme.text.primary
    private var isCellSelected = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.spacing.xs),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.spacing.xs),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setSelected(_ selected: Bool) {
        isCellSelected = selected
        label.textColor = selected ? Theme.accent.violet : baseColor
        label.fadeColor = selected ? Theme.surface.raised : Theme.background.base
        Theme.fill(self, color: selected ? Theme.surface.raised : nil)
    }

    override func layout() {
        super.layout()
        Theme.fill(self, color: isCellSelected ? Theme.surface.raised : nil)
    }
}

final class PlaylistTableView: NSTableView {
    var onDeleteKey: (() -> Void)?
    var onSpaceKey: (() -> Void)?
    var onEnterKey: (() -> Void)?

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
final class PlaylistDataSource: NSTableViewDiffableDataSource<Int, URL> {
    var writerForRow: ((Int) -> NSPasteboardItem?)?
    var validateDropHandler: ((NSDraggingInfo, Int) -> NSDragOperation)?
    var acceptDropHandler: ((NSDraggingInfo, Int) -> Bool)?

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
