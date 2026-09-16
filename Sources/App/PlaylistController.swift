import Analysis
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
    /// «Проанализировать треки» из контекстного меню: считать BPM и тональность по требованию.
    var onAnalyzeSelected: (([URL]) -> Void)?

    private var dataSource: PlaylistDataSource?
    /// Звучащий трек: его строка заливается акцентом ярче обычного выделения (решение владельца
    /// 16.09 ~07:00), чтобы его было видно при включённом Random. nil - воспроизведения нет.
    private var playingURL: URL?
    /// Треки, по которым сейчас считается BPM/тональность: в пустых ячейках стоит плейсхолдер,
    /// как тонкая осевая линия на волне, пока она не посчитана.
    private var analysing: Set<URL> = []
    /// Плейсхолдер занятой ячейки.
    private static let analysisPlaceholder = "·"
    /// Имя автосохранения колонок: ручные ширины владельца переживают перезапуск.
    /// Версия v2 с 2026-09-16: коридоры ширин переписаны, старые сохранённые ширины
    /// (общий минимум 18 pt на всё) выглядели бы как «не починено».
    private static let columnsAutosaveName = "ClaimpPlaylistColumns.v2"
    /// Кегль, под который посчитаны текущие ширины: при смене кегля ширины масштабируются
    /// коэффициентом, а не переписываются токенами (иначе ручная ширина стиралась бы).
    private var widthsFontSize = SettingsStore.shared.value.playlistFontSize
    /// Набор видимых колонок, под который посчитаны текущие ширины.
    private var lastVisibleColumns: Set<String> = []
    /// Настройки, под которые уже разложена таблица. Правило одно на всех потребителей
    /// настроек: применяем только то, что изменилось у нас. Без него любой тик чужого
    /// слайдера перезагружал все строки (замер до правки: 90 мс на тик, 81 тик из 81 > 16 мс).
    private var appliedSettings: AppSettings?
    /// Страж от рекурсии: `sizeToFit` сам стреляет уведомлением о ресайзе колонки.
    private var isFitting = false

    var statusText: String {
        PlaylistSummary.text(for: model.displayed)
    }

    /// Треки под контекстным меню и клавишами: ровно то, что выделено в таблице.
    var selectedURLs: [URL] {
        tableView.selectedRowIndexes.compactMap { rowURL($0) }
    }

    /// Что считать по правому клику: из выделенного только треки без темпа или тональности.
    /// Решение владельца 16.09 (матом): пересчитывать уже размеченные незачем.
    var selectedURLsNeedingAnalysis: [URL] {
        tableView.selectedRowIndexes.compactMap { row in
            guard row < model.displayed.count else { return nil }
            let track = model.displayed[row]
            return (track.bpm == nil || track.key == nil) ? track.url : nil
        }
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

    /// Треки поставлены в очередь анализа: ячейки BPM/Key показывают плейсхолдер.
    func markAnalysing(urls: [URL]) {
        analysing.formUnion(urls)
        for url in urls { refreshAnalysisCells(url: url) }
    }

    /// Разбор готов: значения уходят в модель и в видимые ячейки, без перестроения таблицы -
    /// строка не мигает и выделение не слетает. `inTag` = значения уже в файле, они главнее
    /// прежнего тега.
    func applyAnalysis(url: URL, bpm: Double?, key: String?, inTag: Bool) {
        analysing.remove(url)
        _ = model.applyAnalysis(url: url, bpm: bpm, key: key, inTag: inTag)
        refreshAnalysisCells(url: url)
    }

    /// Разбор этого трека закончился ничем (ошибка, пропуск, отмена): плейсхолдер снимается,
    /// ячейка снова пустая.
    func stopAnalysing(url: URL) {
        analysing.remove(url)
        refreshAnalysisCells(url: url)
    }

    /// Сменился звучащий трек: перекрашиваются ровно две строки (старая и новая), таблица
    /// не перезагружается, выделение не слетает. Плейлист подкручивается к новой строке, если
    /// она вне видимой области; ручной скролл между сменами не дёргается.
    func setPlaying(url: URL?) {
        guard playingURL != url else { return }
        let rows = PlaylistNavigator.rowsToRepaint(
            from: playingURL, to: url, in: model.displayed.map(\.url))
        playingURL = url
        for row in rows { repaintRow(row) }
        guard let url, let row = model.displayed.firstIndex(where: { $0.url == url }) else { return }
        tableView.scrollRowToVisible(row)
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
        tableView.style = .plain
        tableView.selectionHighlightStyle = .none
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        // Порядок колонок владелец тянет рукой (решение 2026-09-16); что можно двигать,
        // решает делегат, а порядок помнит то же автосохранение, что и ширины.
        tableView.allowsColumnReordering = true
        tableView.gridStyleMask = []
        // Воздух между колонками: при нуле столбик цифр прилипал к соседней колонке.
        tableView.intercellSpacing = NSSize(width: Theme.column.intercellWidth, height: 0)
        tableView.backgroundColor = Theme.background.base
        // Раздачу ширины целиком делает `fitColumnsToWindow` (замеры research/08 §4.2):
        // при этом режиме прирост окна расходится по обеим эластичным колонкам поровну,
        // а `sequential`/`lastColumnOnly` отдают его одной.
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.allowsColumnResizing = true

        tableView.headerView = FlatHeaderView()
        for column in PlaylistColumn.allCases {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            let header = FlatHeaderCell(textCell: column.headerTitle)
            header.font = Theme.font.columnHeader
            header.textColor = Theme.text.secondary
            header.alignment = .left
            tableColumn.headerCell = header
            tableColumn.title = column.headerTitle
            if let field = column.sortField {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: field.rawValue, ascending: true)
            }
            column.applyWidth(to: tableColumn)
            tableView.addTableColumn(tableColumn)
        }
        // Автосохранение включается после добавления колонок: иначе восстанавливать нечему.
        tableView.autosaveName = Self.columnsAutosaveName
        tableView.autosaveTableColumns = true
        // Окно меняет ширину - таблица обязана поменять свою следом (и наоборот: при первой
        // раскладке ширина клипа приходит именно сюда). Одно место на все случаи: первый показ,
        // растягивание окна, сужение.
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipDidResize),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)
        NotificationCenter.default.addObserver(
            self, selector: #selector(columnDidResize),
            name: NSTableView.columnDidResizeNotification, object: tableView)

        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)

        // Контекстное меню строки: состав пунктов собирается на каждый показ по выделению.
        let menu = NSMenu()
        menu.delegate = self
        // Доступность пунктов решает `menuNeedsUpdate`, а не автовключение по target/action.
        menu.autoenablesItems = false
        tableView.menu = menu

        tableView.onDeleteKey = { [weak self] in self?.deleteSelected() }
        tableView.onSpaceKey = { [weak self] in self?.onTogglePlay?() }
        tableView.onEnterKey = { [weak self] in
            if let track = self?.selectedTrack { self?.onPlayTrack?(track) }
        }

        let source = PlaylistDataSource(tableView: tableView) { [weak self] tableView, column, _, item in
            self?.makeCell(tableView: tableView, column: column, item: item) ?? NSView()
        }
        source.sortHandler = { [weak self] descriptors in self?.applySort(descriptors) }
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
        applySettings()
        updateSortIndicators()
    }

    // MARK: - Настройки (⌘,)

    /// Настройки применяются на лету, без перезапуска: кегль и высота строки, видимость колонок,
    /// формат тональности. Сами числа считает `Theme` от кегля из `SettingsStore`.
    func applySettings() {
        let settings = SettingsStore.shared.value
        let previous = appliedSettings
        appliedSettings = settings
        // Таблицу задают три настройки: кегль, состав колонок и формат тональности. Всё
        // остальное (высота волны, палитра, яркость, анализ) её не касается.
        guard previous?.playlistFontSize != settings.playlistFontSize
            || previous?.hiddenColumns != settings.hiddenColumns
            || previous?.keyFormat != settings.keyFormat
        else { return }
        let visible = Set(PlaylistColumns.visible(
            all: PlaylistColumn.allCases.map(\.rawValue), hidden: settings.hiddenColumns))
        tableView.rowHeight = Theme.size.row
        let previousSize = widthsFontSize
        widthsFontSize = settings.playlistFontSize
        for tableColumn in tableView.tableColumns {
            let key = tableColumn.identifier.rawValue
            tableColumn.isHidden = !visible.contains(key)
            (tableColumn.headerCell as? FlatHeaderCell)?.font = Theme.font.columnHeader
            // Границы пересчитываются от кегля, а ширина - от своей же прежней: колонку, которую
            // владелец потянул рукой, смена кегля масштабирует, но не сбрасывает токеном.
            PlaylistColumn(rawValue: key)?.applyLimits(to: tableColumn)
            tableColumn.width = CGFloat(PlaylistFont.rescaled(
                width: Double(tableColumn.width), fromRow: previousSize, toRow: settings.playlistFontSize))
        }
        keepOneElasticColumn()
        lastVisibleColumns = visible
        fitColumnsToWindow()
        tableView.headerView?.needsDisplay = true
        reloadCells()
    }

    /// Раздать лишнюю ширину `sizeToFit` может только колонке с `.autoresizingMask`. Владелец
    /// спрятал обе текстовые - маску получает последняя видимая, иначе справа остаётся пустота
    /// (замер прогона: sum=283 при клипе 500).
    private func keepOneElasticColumn() {
        let visible = tableView.tableColumns.filter { !$0.isHidden }
        guard !visible.isEmpty,
            !visible.contains(where: { $0.resizingMask.contains(.autoresizingMask) }),
            let last = visible.last
        else { return }
        last.resizingMask = [.userResizingMask, .autoresizingMask]
    }

    // MARK: - Ширины колонок

    /// Одна функция на все случаи, когда ширины поехали: окно сменило ширину, владелец потянул
    /// разделитель, колонку показали или спрятали, сменился кегль. Ширина таблицы принудительно
    /// равна ширине клипа, а `sizeToFit` раскладывает по ней колонки, двигая только эластичные
    /// (замеры research/08 §2.3, §4.1, §4.3). Своей арифметики дельт нет.
    private func fitColumnsToWindow() {
        guard !isFitting else { return }
        let clipWidth = scrollView.contentView.bounds.width
        guard clipWidth > 0 else { return }
        isFitting = true
        tableView.setFrameSize(NSSize(width: clipWidth, height: tableView.frame.height))
        tableView.sizeToFit()
        // `sizeToFit` двигает только эластичные колонки; если они уже у минимума (владелец
        // схлопнул Title/Artist или вернул их после скрытия), остаток снимаем с крайней.
        let overflow = tableView.frame.width - clipWidth
        if overflow > 0, let last = tableView.tableColumns.last(where: { !$0.isHidden }) {
            last.width = max(last.minWidth, last.width - overflow)
            tableView.setFrameSize(NSSize(width: clipWidth, height: tableView.frame.height))
        }
        isFitting = false
    }

    @objc private func clipDidResize() {
        fitColumnsToWindow()
    }

    /// Владелец потянул разделитель: AppKit меняет одну колонку и растягивает саму таблицу,
    /// поэтому дальше делаем ровно то же, что и при смене ширины окна.
    @objc private func columnDidResize() {
        fitColumnsToWindow()
    }


    // MARK: - Отладочный прогон (CLAIMP_PROBE=1)

    /// Протяжка границы без мыши: AppKit при настоящей протяжке ставит новую ширину одной
    /// колонке, дальше работает наш обработчик. Здесь ровно то же, поэтому прогон меряет
    /// продуктовый путь, а не свою копию логики.
    func simulateUserColumnDrag(_ kind: PlaylistColumn, delta: CGFloat) {
        guard let column = tableView.tableColumns.first(
            where: { $0.identifier.rawValue == kind.rawValue }) else { return }
        column.width = min(max(column.width + delta, column.minWidth), column.maxWidth)
    }

    /// Последняя видимая колонка: её тянет владелец, когда жалуется на пустоту справа.
    var lastVisibleColumn: PlaylistColumn? {
        tableView.tableColumns.last { !$0.isHidden }
            .flatMap { PlaylistColumn(rawValue: $0.identifier.rawValue) }
    }

    /// Строка замера: ширины видимых колонок, их сумма с промежутками, ширина таблицы и клипа.
    /// `fits` - тот самый инвариант «таблица ровно по окну».
    func columnReportLine(_ step: String) -> String {
        let columns = tableView.tableColumns.filter { !$0.isHidden }
        let widths = columns
            .map { "\($0.identifier.rawValue)=\(Int($0.width.rounded()))" }
            .joined(separator: " ")
        let sum = columns.reduce(0) { $0 + $1.width }
            + Theme.column.intercellWidth * CGFloat(max(0, columns.count - 1))
        let table = tableView.frame.width
        let clip = scrollView.contentView.bounds.width
        return "PROBE columns \(step) sum=\(Int(sum.rounded())) table=\(Int(table.rounded()))"
            + " clip=\(Int(clip.rounded())) fits=\(abs(table - clip) < 1) \(widths)"
    }

    /// Перерисовка всех ячеек без перестроения списка: выделение и прокрутка на месте.
    private func reloadCells() {
        guard let dataSource else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reloadItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
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
            cell.setPlaying(track.url == playingURL)
            cell.onTap = { [weak self] in self?.togglePlayed(url: track.url) }
            return cell
        }

        let cell = tableView.makeView(withIdentifier: PlaylistTextCell.identifier, owner: nil) as? PlaylistTextCell
            ?? PlaylistTextCell()
        cell.identifier = PlaylistTextCell.identifier
        cell.label.font = monoFont(for: columnKind)
        cell.baseColor = (columnKind == .title || columnKind == .artist) ? Theme.text.primary : Theme.text.secondary
        cell.label.stringValue = text(track: track, number: index + 1, column: columnKind)
        // Ячейки переиспользуются: подсказку выставляем всегда, иначе она останется от чужой строки.
        cell.toolTip = tooltip(track: track, column: columnKind)
        cell.setSelected(selected)
        cell.setPlaying(track.url == playingURL)
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
        case .bitrate: return track.displayBitrate
        case .bpm: return placeholderIfBusy(track.displayBPM, url: track.url)
        case .key: return placeholderIfBusy(keyText(track.displayKey), url: track.url)
        }
    }

    /// Тональность в формате из настроек (Camelot / нота / оба). Понимаются обе записи тега -
    /// код Camelot («8A») и нота («Am»); в файл мы пишем ноту, а показываем как просит владелец.
    /// Совсем чужая запись («Fmin») остаётся как есть, перевод не выдумываем.
    private func keyText(_ stored: String) -> String {
        guard let key = MusicalKey(tag: stored) else { return stored }
        return key.display(SettingsStore.shared.value.keyFormat)
    }

    /// Пустая ячейка у трека в очереди анализа показывает плейсхолдер, а не пустоту:
    /// «считается» и «нет значения» - разные состояния.
    private func placeholderIfBusy(_ value: String, url: URL) -> String {
        value.isEmpty && analysing.contains(url) ? Self.analysisPlaceholder : value
    }

    /// Подсказка колонки Key: "8A · Am". Тег, который не разбирается как Camelot, показывается
    /// как есть и подсказки не получает.
    private func tooltip(track: Track, column: PlaylistColumn) -> String? {
        guard column == .key, let key = track.key, let parsed = MusicalKey(tag: key) else {
            return nil
        }
        return "\(parsed.camelot) · \(parsed.shortName)"
    }

    /// Обновление готовых значений прямо в живых ячейках (как у лампочки): снапшот не
    /// перестраивается, поэтому таблица не мигает. Невидимые строки возьмут значение из модели,
    /// когда доедут до экрана.
    private func refreshAnalysisCells(url: URL) {
        guard let row = model.displayed.firstIndex(where: { $0.url == url }) else { return }
        let track = model.displayed[row]
        for column in [PlaylistColumn.bpm, PlaylistColumn.key] {
            guard let index = columnIndex(of: column),
                let cell = tableView.view(atColumn: index, row: row, makeIfNecessary: false)
                    as? PlaylistTextCell
            else { continue }
            cell.label.stringValue = text(track: track, number: row + 1, column: column)
            cell.toolTip = tooltip(track: track, column: column)
        }
    }

    /// Перекраска одной строки: ячейки строки узнают, звучит она сейчас или нет.
    /// Невидимые строки возьмут своё при создании ячейки.
    private func repaintRow(_ row: Int) {
        guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { return }
        let playing = rowURL(row) == playingURL
        for cell in rowView.subviews.compactMap({ $0 as? any RowTinting }) {
            cell.setPlaying(playing)
        }
    }

    /// Ячейка ищется по идентификатору колонки, а не по нулевому индексу: порядок колонок
    /// владелец меняет рукой.
    private func refreshLamp(url: URL) {
        guard let row = model.displayed.firstIndex(where: { $0.url == url }),
              let column = columnIndex(of: .played),
              let cell = tableView.view(atColumn: column, row: row, makeIfNecessary: false) as? PlayedDotCell,
              let track = model.displayed[safe: row]
        else { return }
        cell.setLamp(on: track.isPlayed)
    }

    /// Текущее место колонки в таблице: после перестановки заголовков оно уже не совпадает
    /// с порядком `PlaylistColumn.allCases`.
    private func columnIndex(of column: PlaylistColumn) -> Int? {
        tableView.tableColumns.firstIndex { $0.identifier.rawValue == column.rawValue }
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

    // MARK: - Сортировка кликом по заголовку

    /// Вызывает PlaylistDataSource: sortDescriptorsDidChange - метод NSTableViewDataSource,
    /// таблица зовёт его только у своего dataSource, не у делегата.
    /// Чужой ключ дескриптора игнорируется, порядок остаётся прежним.
    func applySort(_ descriptors: [NSSortDescriptor]) {
        guard let descriptor = descriptors.first,
              let key = descriptor.key,
              let field = TrackSortField.forColumnKey(key)
        else { return }
        model.sortField = field
        model.ascending = descriptor.ascending
        updateSortIndicators()
        applySnapshot()
        notifyUpdate()
    }

    /// Треугольник сортировки в заголовке: плоская ячейка рисует его сама, значит ей надо
    /// сказать, по какой колонке и в какую сторону сортируют.
    private func updateSortIndicators() {
        for tableColumn in tableView.tableColumns {
            let sorted = model.sortField?.rawValue == tableColumn.identifier.rawValue
            (tableColumn.headerCell as? FlatHeaderCell)?.sortAscending = sorted ? model.ascending : nil
        }
        tableView.headerView?.needsDisplay = true
    }

    // MARK: - Прочее

    @objc private func doubleClicked() {
        guard tableView.clickedRow >= 0, let url = rowURL(tableView.clickedRow),
              let track = model.displayed.first(where: { $0.url == url })
        else { return }
        onPlayTrack?(track)
    }

    // MARK: - Контекстное меню (правый клик)

    /// Пункты собираются на каждый показ: заголовок зависит от числа выделенных строк,
    /// а на пустом выделении меню не показывается вовсе.
    @objc func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        // Два пункта всегда (владелец 16.09): «недостающие» - только треки без темпа или
        // тональности, «все» - принудительный пересчёт выделенного, если тег кривой.
        let missing = selectedURLsNeedingAnalysis.count
        let analyzeMissing = NSMenuItem(
            title: Strings.analyzeMissing(count: missing),
            action: #selector(analyzeSelected), keyEquivalent: "")
        analyzeMissing.target = self
        analyzeMissing.isEnabled = missing > 0
        menu.addItem(analyzeMissing)
        let reanalyze = NSMenuItem(
            title: Strings.reanalyzeAll(count: urls.count),
            action: #selector(reanalyzeSelected), keyEquivalent: "")
        reanalyze.target = self
        menu.addItem(reanalyze)
        let delete = NSMenuItem(
            title: Strings.removeFromPlaylist, action: #selector(deleteSelectedFromMenu),
            keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
    }

    @objc private func analyzeSelected() {
        let urls = selectedURLsNeedingAnalysis
        guard !urls.isEmpty else { return }
        onAnalyzeSelected?(urls)
    }

    @objc private func reanalyzeSelected() {
        let urls = selectedURLs
        guard !urls.isEmpty else { return }
        onAnalyzeSelected?(urls)
    }

    @objc private func deleteSelectedFromMenu() {
        deleteSelected()
    }

    // MARK: - NSTableViewDelegate (в теле класса: optional-методы из extension AppKit не видит)

    @objc func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PlaylistRowView()
    }

    @objc func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        // Клик по лампочке не меняет выделение строки.
        let clicked = tableView.tableColumns[safe: tableView.clickedColumn]?.identifier.rawValue
        return clicked != PlaylistColumn.played.rawValue
    }

    /// Перетаскивание заголовка: любая колонка едет на любое место правее лампочки.
    /// Саму лампочку не двигают и на её место никого не пускают - она всегда первая.
    @objc func tableView(
        _ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newIndex: Int
    ) -> Bool {
        guard let key = tableView.tableColumns[safe: columnIndex]?.identifier.rawValue else { return false }
        return PlaylistColumns.canReorder(key, toIndex: newIndex)
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
            for cell in rowView.subviews.compactMap({ $0 as? any RowTinting }) {
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

// MARK: - NSMenuDelegate

extension PlaylistController: NSMenuDelegate {}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
