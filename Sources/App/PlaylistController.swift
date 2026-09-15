import AppKit
import Core

/// Таблица плейлиста: diffable-источник (секция одна, id строки - URL),
/// сортировки кликом по заголовку, лампочка, drag-out файла, внутренний move, клавиши.
@MainActor
final class PlaylistController: NSObject {
    let model = PlaylistModel()
    let scrollView = NSScrollView()
    let tableView = PlaylistTableView()

    var onTogglePlayed: ((URL, Bool) -> Void)?
    var onPlayTrack: ((Track) -> Void)?
    var onTogglePlay: (() -> Void)?
    var onSelectionChange: ((Track?) -> Void)?
    var onUpdate: (() -> Void)?
    /// Состав или порядок изменились: дроп, удаление, внутренний move. Поиск и лампочка сюда не входят.
    var onStructureChange: (() -> Void)?

    private var dataSource: PlaylistDataSource?

    var statusText: String {
        PlaylistSummary.text(for: model.displayed)
    }

    var selectedTrack: Track? {
        guard tableView.selectedRow >= 0, tableView.selectedRow < model.displayed.count else { return nil }
        return model.displayed[tableView.selectedRow]
    }

    override init() {
        super.init()
        setupTable()
    }

    // MARK: - Входные действия

    func replaceAll(_ tracks: [Track]) {
        model.replaceAll(tracks)
        applySnapshot()
        notifyStructure()
    }

    func setQuery(_ query: String) {
        model.query = query
        applySnapshot()
        notifyUpdate()
    }

    func togglePlayed(url: URL) {
        model.togglePlayed(url: url)
        refreshLamp(url: url)
        if let track = model.allTracks.first(where: { $0.url == url }) {
            onTogglePlayed?(url, track.isPlayed)
        }
        notifyUpdate()
    }

    func deleteSelected() {
        let urls = Set(tableView.selectedRowIndexes.compactMap { rowURL($0) })
        guard !urls.isEmpty else { return }
        model.remove(urls: urls)
        applySnapshot()
        notifyStructure()
    }

    func select(url: URL?) {
        guard let url, let row = model.displayed.firstIndex(where: { $0.url == url }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    // MARK: - Сборка

    private func setupTable() {
        tableView.delegate = self
        tableView.rowHeight = Theme.size.row
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.allowsColumnReordering = false
        tableView.gridStyleMask = []
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = Theme.background.base
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        tableView.headerView = FlatHeaderView()
        for column in PlaylistColumn.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            let header = FlatHeaderCell(textCell: column.headerTitle)
            header.font = Theme.font.columnHeader
            header.textColor = Theme.text.secondary
            header.alignment = column.alignsRight ? .right : .left
            tableColumn.headerCell = header
            tableColumn.title = column.headerTitle
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.sortField.rawValue, ascending: true)
            column.applyWidth(to: tableColumn)
            tableView.addTableColumn(tableColumn)
        }

        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)

        tableView.onDeleteKey = { [weak self] in self?.deleteSelected() }
        tableView.onSpaceKey = { [weak self] in self?.onTogglePlay?() }
        tableView.onEnterKey = { [weak self] in
            if let track = self?.selectedTrack { self?.onPlayTrack?(track) }
        }

        let source = PlaylistDataSource(tableView: tableView) { [weak self] tableView, column, _, item in
            self?.makeCell(tableView: tableView, column: column, item: item) ?? NSView()
        }
        source.writerForRow = { [weak self] row in self?.pasteboardItem(forRow: row) }
        source.validateDropHandler = { [weak self] info, row in self?.validateDrop(info: info, row: row) ?? [] }
        source.acceptDropHandler = { [weak self] info, row in self?.acceptDrop(info: info, row: row) ?? false }
        tableView.dataSource = source
        dataSource = source

        tableView.registerForDraggedTypes([.string])
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        scrollView.documentView = tableView
        // Ширина таблицы = ширина окна: иначе при 420 pt последняя колонка уезжает за край.
        tableView.autoresizingMask = [.width]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background.base
        scrollView.contentView.drawsBackground = true
        scrollView.contentView.backgroundColor = Theme.background.base
        scrollView.borderType = .noBorder

        applySnapshot()
    }

    // MARK: - Снапшот и ячейки

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, URL>()
        snapshot.appendSections([0])
        snapshot.appendItems(model.displayed.map(\.url))
        dataSource?.apply(snapshot, animatingDifferences: false)
    }

    private func rowURL(_ row: Int) -> URL? {
        guard row >= 0, row < model.displayed.count else { return nil }
        return model.displayed[row].url
    }

    private func makeCell(tableView: NSTableView, column: NSTableColumn, item: URL) -> NSView? {
        guard let columnKind = PlaylistColumn(rawValue: column.identifier.rawValue) else { return nil }
        guard let index = model.displayed.firstIndex(where: { $0.url == item }) else { return nil }
        let track = model.displayed[index]
        let selected = tableView.selectedRowIndexes.contains(index)

        if columnKind == .played {
            let cell = tableView.makeView(withIdentifier: PlayedDotCell.identifier, owner: nil) as? PlayedDotCell
                ?? PlayedDotCell()
            cell.identifier = PlayedDotCell.identifier
            cell.setLamp(on: track.isPlayed)
            cell.setSelected(selected)
            cell.onTap = { [weak self] in self?.togglePlayed(url: track.url) }
            return cell
        }

        let cell = tableView.makeView(withIdentifier: PlaylistTextCell.identifier, owner: nil) as? PlaylistTextCell
            ?? PlaylistTextCell()
        cell.identifier = PlaylistTextCell.identifier
        cell.label.font = monoFont(for: columnKind)
        cell.label.alignment = columnKind.alignsRight ? .right : .left
        cell.baseColor = (columnKind == .title || columnKind == .artist) ? Theme.text.primary : Theme.text.secondary
        cell.label.stringValue = text(track: track, number: index + 1, column: columnKind)
        cell.setSelected(selected)
        return cell
    }

    private func monoFont(for column: PlaylistColumn) -> NSFont {
        column == .title || column == .artist ? Theme.font.row : Theme.font.rowDigits
    }

    private func text(track: Track, number: Int, column: PlaylistColumn) -> String {
        switch column {
        case .played: return ""
        case .number: return String(number)
        case .title: return track.title
        case .artist: return track.artist
        case .year: return track.displayYear
        case .duration: return track.displayDuration
        }
    }

    private func refreshLamp(url: URL) {
        guard let row = model.displayed.firstIndex(where: { $0.url == url }),
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? PlayedDotCell,
              let track = model.displayed[safe: row]
        else { return }
        cell.setLamp(on: track.isPlayed)
    }

    // MARK: - Drag-out (главный пункт задачи)

    private func pasteboardItem(forRow row: Int) -> NSPasteboardItem? {
        guard let url = rowURL(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .string)
        item.setString(url.absoluteString, forType: .fileURL)
        return item
    }

    private func validateDrop(info: NSDraggingInfo, row: Int) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView else { return [] }
        guard info.draggingPasteboard.canReadObject(forClasses: [NSString.self], options: nil) else { return [] }
        return .move
    }

    private func acceptDrop(info: NSDraggingInfo, row: Int) -> Bool {
        guard let strings = info.draggingPasteboard.readObjects(forClasses: [NSString.self], options: nil) as? [String] else {
            return false
        }
        let rows = strings.compactMap(Int.init).sorted()
        let moved = rows.compactMap { rowURL($0) }
        guard moved.count == rows.count, !moved.isEmpty else { return false }
        // Цель в координатах до удаления: строки выше цели сдвигаются вниз.
        let above = rows.filter { $0 < row }.count
        model.moveDisplayed(urls: moved, toRow: row - above)
        tableView.sortDescriptors = []
        applySnapshot()
        notifyStructure()
        return true
    }

    // MARK: - Прочее

    @objc private func doubleClicked() {
        guard tableView.clickedRow >= 0, let url = rowURL(tableView.clickedRow),
              let track = model.displayed.first(where: { $0.url == url })
        else { return }
        onPlayTrack?(track)
    }

    // MARK: - NSTableViewDelegate (в теле класса: optional-методы из extension AppKit не видит)

    @objc func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PlaylistRowView()
    }

    @objc func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let key = tableView.sortDescriptors.first?.key,
              let field = TrackSortField(rawValue: key)
        else { return }
        model.sortField = field
        model.ascending = tableView.sortDescriptors.first?.ascending ?? true
        applySnapshot()
        notifyUpdate()
    }

    @objc func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        // Клик по лампочке не меняет выделение строки.
        let clicked = tableView.tableColumns[safe: tableView.clickedColumn]?.identifier.rawValue
        return clicked != PlaylistColumn.played.rawValue
    }

    @objc func tableViewSelectionDidChange(_ notification: Notification) {
        refreshVisibleSelection()
        onSelectionChange?(selectedTrack)
    }

    /// Системное выделение выключено (.none): акцент рисуют сами ячейки.
    private func refreshVisibleSelection() {
        let visible = tableView.rows(in: tableView.visibleRect)
        for row in visible.lowerBound..<visible.upperBound {
            let selected = tableView.selectedRowIndexes.contains(row)
            guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { continue }
            for cell in rowView.subviews.compactMap({ $0 as? any SelectionTinting }) {
                cell.setSelected(selected)
            }
        }
    }

    private func notifyUpdate() {
        onSelectionChange?(selectedTrack)
        onUpdate?()
    }

    private func notifyStructure() {
        notifyUpdate()
        onStructureChange?()
    }
}

// MARK: - NSTableViewDelegate

extension PlaylistController: NSTableViewDelegate {}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
