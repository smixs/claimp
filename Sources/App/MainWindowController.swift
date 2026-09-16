import AppKit
import Core
import Playback
import Waveform

/// Окно 500×760 (минимум 420×600) по SPEC §4.1. Всё @MainActor, своих очередей нет.
/// Склейка T5: движок, Now Playing, волна через кэш, лампочки и плейлист в PlayedStore.
@MainActor
final class MainWindowController {
    /// В UserDefaults лежит ПОЗИЦИЯ ручки 0…1, не усиление: старое линейное значение
    /// прошлой версии читается как позиция, отдельной миграции не нужно.
    private static let volumeKey = "Claimp.volume"
    private static let defaultVolumePosition: Double = 0.8

    let window: NSWindow
    private let playlist = PlaylistController()
    private let header = HeaderView()
    private let wave = WaveformView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let search = NSSearchField()
    private let scanner = LibraryScanner()
    private let engine = PlayerEngine()
    private let nowPlaying = NowPlayingBridge()
    private let analyzer = WaveformAnalyzer()
    /// Фоновый разбор BPM/тональности для треков без тега.
    private let analysisRunner: AnalysisRunner

    /// nil, если боевой SQLite не открылся: лампочки и порядок тогда не сохраняются, причина висит
    /// красным в статусной строке. Подмены памятью нет - правило «фолбэков и тихих пропусков нет».
    private let store: PlayedStoring?
    /// Причина, по которой не работают лампочки: живёт до выхода, показывается после свежих ошибок.
    private let storeFailure: String?

    /// Высота блока волны: меняется слайдером в настройках без перезапуска.
    private var waveHeightConstraint: NSLayoutConstraint?

    /// Транспорт живёт внутри верхнего блока: обложка занимает всю его высоту.
    private var transport: TransportView { header.transport }

    /// Последняя ошибка (движка, волны или базы): висит в статусной строке, пока не заиграет
    /// следующий трек или не начнётся новый анализ волны.
    private var errorText: String?
    /// Сколько треков не разобралось в этой сессии: висит счётчиком в статусной строке,
    /// каждая причина отдельно уходит в stderr. Остальные треки при этом продолжают считаться.
    private var analysisErrors = 0

    /// Подписка на изменения настроек: снимается вместе с контроллером.
    private var settingsObserver: NSObjectProtocol?
    /// Настройки, которые уже применены к окну: высота волны меняется только при её изменении.
    private var appliedSettings: AppSettings?

    private var positionsTask: Task<Void, Never>?
    private var waveTask: Task<Void, Never>?
    /// Трек, чьи данные сейчас на волне: повторный выбор той же строки анализ не перезапускает.
    private var waveURL: URL?
    private var lastElapsed: TimeInterval = 0

    init() {
        let opened = Self.openStore()
        store = opened.store
        storeFailure = opened.failure
        analysisRunner = AnalysisRunner(store: opened.store, settings: SettingsStore.shared.value)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Theme.size.windowWidth, height: Theme.size.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claimp"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = NSSize(width: Theme.size.windowMinWidth, height: Theme.size.windowMinHeight)
        window.appearance = NSAppearance(named: .darkAqua)
        window.setFrameAutosaveName("ClaimpMain")

        let root = DropReceiverView()
        root.onDropURLs = { [weak self] urls in self?.loadURLs(urls) }
        window.contentView = root

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        let logo = TitlebarLogo.makeView()
        root.addSubview(logo)
        // Центр логотипа - строго на оси светофоров; точное смещение берётся у самих кнопок
        // ниже, константа здесь только чтобы констрейнт был полным до первого замера.
        let logoCenter = logo.centerYAnchor.constraint(
            equalTo: root.topAnchor, constant: Theme.size.titlebar / 2
        )
        NSLayoutConstraint.activate([
            // Контент идёт под прозрачным титлбаром, логотип живёт в его полосе.
            logo.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Theme.size.logoLeading),
            logoCenter,

            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Theme.size.titlebar),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        Self.align(logoCenter: logoCenter, toButtonsOf: window, in: root)

        header.translatesAutoresizingMaskIntoConstraints = false
        header.heightAnchor.constraint(equalToConstant: Theme.size.headerStrip).isActive = true
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        header.volume.position = Self.loadVolumePosition()

        // Волна T6 со своей полосой времени: высота волны в процентах живёт в настройках
        // (решение владельца 2026-09-16), освободившееся место забирает плейлист.
        wave.translatesAutoresizingMaskIntoConstraints = false
        let waveHeight = wave.heightAnchor.constraint(
            equalToConstant: WaveformView.blockHeight(percent: SettingsStore.shared.value.waveHeightPercent))
        waveHeight.isActive = true
        waveHeightConstraint = waveHeight
        wave.onSeek = { [weak self] fraction in self?.seek(fraction: fraction) }
        stack.addArrangedSubview(wave)
        wave.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        playlist.scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(playlist.scrollView)
        playlist.scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        statusLabel.font = Theme.font.status
        statusLabel.textColor = Theme.text.secondary
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.heightAnchor.constraint(equalToConstant: Theme.size.statusStrip).isActive = true
        stack.addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let searchStrip = NSView()
        Theme.fill(searchStrip, color: Theme.background.base)
        searchStrip.translatesAutoresizingMaskIntoConstraints = false
        searchStrip.heightAnchor.constraint(equalToConstant: Theme.size.searchStrip).isActive = true
        let searchBacking = NSView()
        Theme.fill(searchBacking, color: Theme.surface.inset, radius: Theme.radius.small)
        searchBacking.translatesAutoresizingMaskIntoConstraints = false
        search.translatesAutoresizingMaskIntoConstraints = false
        search.isBezeled = false
        search.drawsBackground = false
        search.focusRingType = .none
        search.placeholderAttributedString = NSAttributedString(
            string: Strings.search,
            attributes: [.foregroundColor: Theme.text.secondary, .font: Theme.font.search]
        )
        search.font = Theme.font.search
        search.textColor = Theme.text.primary
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        searchBacking.addSubview(search)
        searchStrip.addSubview(searchBacking)
        NSLayoutConstraint.activate([
            searchBacking.leadingAnchor.constraint(equalTo: searchStrip.leadingAnchor, constant: Theme.spacing.s),
            searchBacking.trailingAnchor.constraint(equalTo: searchStrip.trailingAnchor, constant: -Theme.spacing.s),
            searchBacking.topAnchor.constraint(equalTo: searchStrip.topAnchor, constant: Theme.spacing.xs),
            searchBacking.bottomAnchor.constraint(equalTo: searchStrip.bottomAnchor, constant: -Theme.spacing.xs),
            search.leadingAnchor.constraint(equalTo: searchBacking.leadingAnchor, constant: Theme.spacing.s),
            search.trailingAnchor.constraint(equalTo: searchBacking.trailingAnchor, constant: -Theme.spacing.s),
            search.centerYAnchor.constraint(equalTo: searchBacking.centerYAnchor),
        ])
        stack.addArrangedSubview(searchStrip)
        searchStrip.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        engine.volume = VolumeCurve.gain(forPosition: Self.loadVolumePosition())
        engine.onEndOfTrack = { [weak self] in self?.trackEnded() }
        engine.onError = { [weak self] error in self?.report(error) }
        wirePlaylist()
        wireAnalysis()
        wireSettings()
        wireTransport()
        wireRemote()
        nowPlaying.register()
        consumePositions()
        header.show(track: nil)
        refreshChrome()
        restore()
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Отладочный прогон (`--probe` / `CLAIMP_PROBE=1`): числа по колонкам и время одного тика
    /// слайдера высоты волны, всё в stderr. Мыши у прогона нет, поэтому сценарии владельца
    /// воспроизводятся теми же вызовами, какими их делает AppKit.
    func runProbe(width: CGFloat?) {
        if let width { setWindowWidth(width) }
        waitForProbeReady(attempt: 0)
    }

    /// Прогон стартует по готовым данным: пустой плейлист и пустая волна мерили бы не то,
    /// на что жалуется владелец. Ждём восстановления библиотеки и волны, но не бесконечно.
    private func waitForProbeReady(attempt: Int) {
        let ready = !playlist.model.displayed.isEmpty && wave.data != nil
        guard !ready, attempt < 120 else {
            probeReport("PROBE ready rows=\(playlist.model.displayed.count) wave=\(wave.data != nil)"
                + " attempt=\(attempt)")
            probeColumns()
            probeWaveHeightTicks()
            probeInteractionTicks()
            probeIdle()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForProbeReady(attempt: attempt + 1)
        }
    }

    private func setWindowWidth(_ width: CGFloat) {
        var frame = window.frame
        frame.size.width = width
        window.setFrame(frame, display: true)
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// Три сценария владельца числами: ужатие крайней колонки, протяжка средней, окно 500→900.
    /// Плюс случай «обе эластичные колонки спрятаны» (риск research/08 §5.4).
    private func probeColumns() {
        probeReport(playlist.columnReportLine("start"))
        if let last = playlist.lastVisibleColumn {
            playlist.simulateUserColumnDrag(last, delta: 20)
            probeReport(playlist.columnReportLine("widen-last+20"))
            playlist.simulateUserColumnDrag(last, delta: -20)
            probeReport(playlist.columnReportLine("shrink-last-20"))
        }
        playlist.simulateUserColumnDrag(.year, delta: 40)
        probeReport(playlist.columnReportLine("drag-year+40"))
        playlist.simulateUserColumnDrag(.year, delta: -40)
        setWindowWidth(900)
        probeReport(playlist.columnReportLine("window-900"))
        setWindowWidth(500)
        probeReport(playlist.columnReportLine("window-500"))
        let hidden = SettingsStore.shared.value.hiddenColumns
        SettingsStore.shared.update { $0.hiddenColumns = hidden.union(["title", "artist"]) }
        window.contentView?.layoutSubtreeIfNeeded()
        probeReport(playlist.columnReportLine("no-elastic-visible"))
        SettingsStore.shared.update { $0.hiddenColumns = hidden }
        window.contentView?.layoutSubtreeIfNeeded()
        probeReport(playlist.columnReportLine("restored"))
    }

    /// Протяжка слайдера высоты волны: каждый тик - полный круг «настройка → подписчики →
    /// раскладка → слои». Меряем этот круг, а не отдельную функцию.
    private func probeWaveHeightTicks() {
        let start = SettingsStore.shared.value.waveHeightPercent
        var samples: [Double] = []
        for percent in WaveHeight.range {
            let t0 = CFAbsoluteTimeGetCurrent()
            SettingsStore.shared.update { $0.waveHeightPercent = percent }
            window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            samples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        SettingsStore.shared.update { $0.waveHeightPercent = start }
        let sorted = samples.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        let over16 = samples.filter { $0 > 16 }.count
        probeReport(String(
            format: "PROBE waveheight ticks=%d median=%.2fms max=%.2fms over16ms=%d total=%.1fms",
            samples.count, median, sorted.last ?? 0, over16, samples.reduce(0, +)))
        probeReport("PROBE waveheight samples " + samples.map { String(format: "%.1f", $0) }.joined(separator: ","))
    }

    /// Остальные протяжки владельца: разделитель колонок, ширина окна, прокрутка плейлиста.
    /// Меряется то же, что и у слайдера высоты: круг «действие → раскладка → слои».
    private func probeInteractionTicks() {
        measureTicks(name: "column-drag", count: 40) { [weak self] step in
            self?.playlist.simulateUserColumnDrag(.year, delta: step.isMultiple(of: 2) ? 4 : -4)
        }
        let startWidth = window.frame.width
        measureTicks(name: "window-resize", count: 40) { [weak self] step in
            self?.setWindowWidth(500 + CGFloat(step) * 10)
        }
        setWindowWidth(startWidth)
        let rows = playlist.model.displayed.count
        measureTicks(name: "scroll", count: 40) { [weak self] step in
            guard let self, rows > 0 else { return }
            playlist.tableView.scrollRowToVisible(min(rows - 1, step * 3))
        }
    }

    /// Один замер: действие плюс принудительная раскладка и отправка слоёв, как на живом кадре.
    private func measureTicks(name: String, count: Int, step: @escaping (Int) -> Void) {
        var samples: [Double] = []
        for index in 0..<count {
            let t0 = CFAbsoluteTimeGetCurrent()
            step(index)
            window.contentView?.layoutSubtreeIfNeeded()
            CATransaction.flush()
            samples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        let sorted = samples.sorted()
        probeReport(String(
            format: "PROBE %@ ticks=%d median=%.2fms max=%.2fms over16ms=%d",
            name, samples.count, sorted[sorted.count / 2], sorted.last ?? 0,
            samples.filter { $0 > 16 }.count))
    }

    /// Покой: сколько памяти держит процесс и тикают ли таймеры без воспроизведения.
    private func probeIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            probeReport(String(format: "PROBE idle rssMB=%.1f pid=%d", Self.residentMegabytes(), getpid()))
        }
    }

    private static func residentMegabytes() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Double(info.resident_size) / 1_048_576
    }

    // MARK: - Магазин лампочек

    /// Боевая база открывается один раз; памятью её не подменяем: не открылась - лампочки и порядок
    /// между запусками не работают, и об этом сказано явно (красная статусная строка и stderr).
    private static func openStore() -> (store: PlayedStoring?, failure: String?) {
        do {
            return (try PlayedStore.makeDefault(), nil)
        } catch {
            let reason = Strings.Error.storeUnavailable(
                Strings.Error.storeNotOpened(error.localizedDescription))
            FileHandle.standardError.write(Data("Claimp: \(reason)\n".utf8))
            return (nil, reason)
        }
    }

    // MARK: - Загрузка извне (дроп, Dock, ⌘O)

    /// Дроп заменяет плейлист целиком. Без аудио - плейлист прежний, без падений.
    func loadURLs(_ urls: [URL]) {
        Task { [weak self] in
            guard let self else { return }
            let tracks = await self.scan(urls)
            guard !tracks.isEmpty else { return }
            self.applyScanned(tracks)
        }
    }

    func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = Strings.openPanelPrompt
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.loadURLs(panel.urls)
        }
    }

    private func scan(_ urls: [URL]) async -> [Track] {
        var tracks: [Track] = []
        for url in urls {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                tracks += await scanner.scan(folder: url)
            } else if let track = await scanner.track(at: url) {
                tracks.append(track)
            }
        }
        return tracks
    }

    /// Свежие треки в таблицу: лампочки из базы поверх, порядок и текущий - в базу.
    private func applyScanned(_ tracks: [Track]) {
        var flagged = tracks
        if let store {
            do {
                let played = try store.playedURLs(among: tracks.map(\.url))
                for index in flagged.indices where played.contains(flagged[index].url) {
                    flagged[index].isPlayed = true
                }
            } catch {
                reportDatabase(error)
            }
        }
        playlist.replaceAll(flagged)
        persist()
        analysisRunner.start(tracks: flagged)
        if Self.shouldPlayFirstTrack() { playSelectedOrFirst() }
    }

    /// Отладочный ключ, как `--open-settings`: сразу после загрузки папки играет первый трек
    /// (`CLAIMP_PLAY_FIRST=1`). Нужен для снимков подсветки играющей строки без клавиатуры и мыши.
    private static func shouldPlayFirstTrack() -> Bool {
        ProcessInfo.processInfo.environment["CLAIMP_PLAY_FIRST"] == "1"
    }

    // MARK: - Восстановление при запуске

    private func restore() {
        Task { [weak self] in
            guard let self else { return }
            guard let store = self.store else { return }
            let saved: PlaylistState
            do {
                saved = try store.loadPlaylist()
            } catch {
                self.reportDatabase(error)
                return
            }
            let restored = PlaylistNavigator.restore(
                urls: saved.urls,
                current: saved.current,
                isExisting: { FileManager.default.fileExists(atPath: $0.path) }
            )
            var tracks: [Track] = []
            for url in restored.urls {
                if let track = await self.scanner.track(at: url) { tracks.append(track) }
            }
            guard !tracks.isEmpty else { return }
            self.applyScanned(tracks)
            self.playlist.select(url: restored.current ?? tracks.first?.url)
            // Восстановленный текущий трек: шапка и волна сразу, без нажатия play.
            self.showCurrentTrack()
        }
    }

    /// Порядок и текущий трек - в базу после каждого изменения структуры.
    private func persist() {
        guard let store else { return }
        do {
            try store.savePlaylist(playlist.model.allTracks.map(\.url), current: engine.currentURL)
        } catch {
            reportDatabase(error)
        }
    }

    // MARK: - Связывание

    private func wirePlaylist() {
        playlist.onTogglePlayed = { [weak self] url, value in
            guard let self else { return }
            guard let store = self.store else {
                // Клик по лампочке без базы - не тихий пропуск: причина снова идёт в статусную строку.
                self.showError(
                    self.storeFailure ?? Strings.Error.storeUnavailable(Strings.Error.storeMissing))
                return
            }
            do {
                try store.setPlayed(url, value)
            } catch {
                self.reportDatabase(error)
            }
        }
        playlist.onPlayTrack = { [weak self] track in
            self?.play(track: track)
        }
        playlist.onTogglePlay = { [weak self] in
            self?.togglePlay()
        }
        playlist.onSelectionChange = { [weak self] _ in
            self?.showCurrentTrack()
        }
        playlist.onUpdate = { [weak self] in
            self?.showCurrentTrack()
        }
        playlist.onStructureChange = { [weak self] in
            self?.persist()
        }
        // Правый клик «Проанализировать треки»: считаем заново, кэш перезаписывается.
        playlist.onAnalyzeSelected = { [weak self] urls in
            self?.analysisRunner.analyze(urls: urls, force: true)
        }
    }

    /// Разбор идёт в фоне: готовые значения садятся в ячейки по мере готовности, ошибки
    /// считаются, пропуски длинных миксов проговариваются в stderr.
    private func wireAnalysis() {
        analysisRunner.onQueued = { [weak self] urls in
            self?.playlist.markAnalysing(urls: urls)
        }
        analysisRunner.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .ready(let url, let bpm, let key, let inTag):
                self.playlist.applyAnalysis(url: url, bpm: bpm, key: key, inTag: inTag)
            case .skipped(let url, let reason):
                self.playlist.stopAnalysing(url: url)
                FileHandle.standardError.write(
                    Data("Claimp: \(Strings.Error.analysisSkipped(url.lastPathComponent, reason: reason))\n".utf8))
            case .failed(let url, let reason, let bpm, let key):
                // Значения показываем, даже если тег или кэш не записались: счётчик ошибок
                // и stderr скажут, что именно не получилось.
                self.playlist.applyAnalysis(url: url, bpm: bpm, key: key, inTag: false)
                self.analysisErrors += 1
                FileHandle.standardError.write(
                    Data("Claimp: \(Strings.Error.analysisFailed(url.lastPathComponent, reason: reason))\n".utf8))
                self.refreshChrome()
            case .cancelled(let url):
                self.playlist.stopAnalysing(url: url)
            }
        }
    }

    /// Настройки (⌘,): подписка на изменения и применение без перезапуска.
    private func wireSettings() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: SettingsStore.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        applySettings()
    }

    /// Живое применение настроек: плейлист (кегль, колонки, формат тональности), палитра и
    /// яркость волны, диапазон и порог анализа.
    private func applySettings() {
        let settings = SettingsStore.shared.value
        let previous = appliedSettings
        appliedSettings = settings
        // Каждый потребитель берёт только свою настройку и только когда она изменилась:
        // таблица - в `playlist.applySettings`, стиль волны - в `didSet` у `WaveformView`.
        playlist.applySettings()
        transport.isShuffling = settings.shuffle
        if previous?.waveHeightPercent != settings.waveHeightPercent {
            waveHeightConstraint?.constant = WaveformView.blockHeight(percent: settings.waveHeightPercent)
        }
        wave.style = Self.waveStyle(for: settings)
        analysisRunner.apply(settings: settings)
    }

    /// Стиль волны из настроек: спектр или один тон, яркость несыгранной части.
    /// Обе палитры живут в `WaveformStyle` - литералов волны здесь нет.
    private static func waveStyle(for settings: AppSettings) -> WaveformStyle {
        var style = settings.wavePalette == .single ? WaveformStyle.monochrome : WaveformStyle.default
        style.unplayedBrightness = settings.waveUnplayedBrightness
        return style
    }

    /// Окно настроек: пункт меню «Claimp → Настройки…», ⌘, и отладочный ключ запуска.
    func showSettings() {
        SettingsWindowController.shared.show()
    }

    /// Выход из приложения: незавершённый разбор гасится вместе с сессиями анализа.
    func cancelAnalysis() {
        analysisRunner.cancel()
    }

    private func wireTransport() {
        transport.onPlay = { [weak self] in self?.playSelectedOrFirst() }
        transport.onPause = { [weak self] in self?.engine.pause(); self?.afterTransportChange() }
        transport.onStop = { [weak self] in self?.stop() }
        transport.onPrevious = { [weak self] in self?.step(by: -1) }
        transport.onNext = { [weak self] in self?.step(by: 1) }
        transport.onShuffle = { on in SettingsStore.shared.update { $0.shuffle = on } }
        header.volume.onChange = { [weak self] position in
            // Ход ручки линейный, громкость движка - логарифмическая (audio taper).
            self?.engine.volume = VolumeCurve.gain(forPosition: position)
            UserDefaults.standard.set(position, forKey: MainWindowController.volumeKey)
        }
    }

    /// Медиаклавиши и Пункт управления: те же действия App, что и кнопки транспорта.
    private func wireRemote() {
        nowPlaying.onPlay = { [weak self] in self?.playSelectedOrFirst() }
        nowPlaying.onPause = { [weak self] in self?.engine.pause(); self?.afterTransportChange() }
        nowPlaying.onToggle = { [weak self] in self?.togglePlay() }
        nowPlaying.onNext = { [weak self] in self?.step(by: 1) }
        nowPlaying.onPrevious = { [weak self] in self?.step(by: -1) }
    }

    /// Логотип ровно на оси светофоров (правка владельца 15.09): высоту титлбара и
    /// положение кнопок задаёт система, поэтому смещение берётся у самой кнопки закрытия,
    /// а не подбирается константой. Fail fast: окно .titled без кнопки - выравнивать не по чему.
    private static func align(logoCenter: NSLayoutConstraint, toButtonsOf window: NSWindow, in root: NSView) {
        guard let close = window.standardWindowButton(.closeButton) else {
            fatalError("window without a close button: nothing to align the logo to")
        }
        let button = close.convert(close.bounds, to: root)
        logoCenter.constant = root.isFlipped ? button.midY : root.bounds.maxY - button.midY
    }

    private static func loadVolumePosition() -> Double {
        guard UserDefaults.standard.object(forKey: volumeKey) != nil else {
            return defaultVolumePosition
        }
        return UserDefaults.standard.double(forKey: volumeKey)
    }

    // MARK: - Воспроизведение

    /// Fail fast (§6.16): не открылся - алерт с путём и причиной, без автоперехода.
    private func play(track: Track) {
        do {
            try engine.load(track.url)
            try engine.play()
        } catch {
            showPlaybackError(url: track.url, error: error)
            return
        }
        errorText = nil
        playlist.select(url: track.url)
        startWave(for: track)
        afterTransportChange()
        persist()
    }

    private func playSelectedOrFirst() {
        if let track = playlist.selectedTrack ?? playlist.model.displayed.first {
            play(track: track)
        }
    }

    private func togglePlay() {
        switch engine.state {
        case .playing:
            engine.pause()
            afterTransportChange()
        case .paused:
            do {
                try engine.play()
                afterTransportChange()
            } catch {
                showPlaybackError(url: engine.currentURL, error: error)
            }
        case .idle:
            playSelectedOrFirst()
        }
    }

    private func stop() {
        engine.stop()
        nowPlaying.clear()
        afterTransportChange()
    }

    private func seek(fraction: Double) {
        engine.seek(fraction: fraction)
        refreshNowPlaying()
    }

    /// Конец трека: следующий по текущему порядку строк.
    /// Последний - воспроизведение встаёт, курсор остаётся в конце (SPEC §6.4):
    /// движок уже опубликовал долю 1, `stop()` вернул бы курсор в начало.
    /// Лампочка автоматом не ставится.
    private func trackEnded() {
        let visible = playlist.model.displayed.map(\.url)
        guard let next = nextURL(in: visible),
              let track = playlist.model.displayed.first(where: { $0.url == next })
        else {
            afterTransportChange()
            return
        }
        play(track: track)
    }

    private func step(by direction: Int) {
        let visible = playlist.model.displayed
        guard !visible.isEmpty else { return }
        let urls = visible.map(\.url)
        let target: URL?
        if direction > 0 {
            target = nextURL(in: urls)
        } else {
            target = PlaylistNavigator.previous(before: engine.currentURL, in: urls)
        }
        guard let target, let track = visible.first(where: { $0.url == target }) else {
            engine.stop()
            afterTransportChange()
            return
        }
        play(track: track)
    }

    /// Следующий трек одной точкой для кнопки, медиаклавиши и автоперехода в конце трека:
    /// при включённом Random - случайный из видимых строк, иначе следующий по порядку.
    private func nextURL(in urls: [URL]) -> URL? {
        guard SettingsStore.shared.value.shuffle else {
            return PlaylistNavigator.next(after: engine.currentURL, in: urls)
        }
        var generator = SystemRandomNumberGenerator()
        return PlaylistNavigator.random(excluding: engine.currentURL, in: urls, using: &generator)
    }

    private func afterTransportChange() {
        transport.isPlaying = engine.state == .playing
        // Звучащий трек ярко подсвечен в плейлисте, пока движок его держит (играет или на паузе);
        // остановка гасит подсветку. Тот же критерий, что у шапки и волны.
        playlist.setPlaying(url: engine.state == .idle ? nil : engine.currentURL)
        refreshNowPlaying()
        showCurrentTrack()
    }

    /// Один канал для всех ошибок: красный текст в статусной строке и строка в stderr.
    private func showError(_ text: String) {
        FileHandle.standardError.write(Data("Claimp: \(text)\n".utf8))
        errorText = text
        refreshChrome()
    }

    /// Ошибки движка не глотаем: текст в статусную строку красным и строка в stderr.
    private func report(_ error: PlayerEngineError) {
        showError(Self.message(for: error))
    }

    /// Ошибки базы раньше жили только в NSLog: владелец не знал, что лампочки не сохраняются.
    private func reportDatabase(_ error: Error) {
        showError(Strings.Error.storeUnavailable(error.localizedDescription))
    }

    private static func message(for error: PlayerEngineError) -> String {
        switch error {
        case .cannotOpen(let url):
            return Strings.Error.playbackCannotOpen(url.lastPathComponent)
        case .notLoaded:
            return Strings.Error.playbackNotLoaded
        }
    }

    /// Тексты ошибок волны: испорченный кэш и обрыв чтения - разные причины для владельца.
    private static func message(for error: WaveformError, file: String) -> String {
        switch error {
        case .cannotOpen:
            return Strings.Error.waveCannotOpen(file)
        case .cannotRead(_, let frame):
            return Strings.Error.waveCannotRead(file, frame: frame)
        case .badCache:
            return Strings.Error.waveBadCache(file)
        case .cancelled:
            return Strings.Error.waveCancelled
        }
    }

    private func showPlaybackError(url: URL?, error: Error) {
        let alert = NSAlert()
        alert.messageText = Strings.Error.playbackFailedTitle
        alert.informativeText = "\(url?.path ?? "—")\n\(error.localizedDescription)"
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    // MARK: - Волна

    private func startWave(for track: Track) {
        waveTask?.cancel()
        waveURL = track.url
        // Ошибка прошлой волны снимается новым анализом: она была про другой файл.
        errorText = nil
        wave.data = nil
        wave.duration = track.duration
        wave.progress = 0
        lastElapsed = 0
        let started = Date()
        waveTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.analyzer.analyze(url: track.url)
                try Task.checkCancellation()
                self.wave.data = data
                NSLog("T5 wave ready: %@ in %.2f s", track.url.lastPathComponent, Date().timeIntervalSince(started))
            } catch let error as WaveformError {
                // Отмена - не ошибка: владелец выбрал другой трек, волна уедет за новым.
                guard error != .cancelled else { return }
                self.showError(Self.message(for: error, file: track.url.lastPathComponent))
            } catch is CancellationError {
                return
            } catch {
                self.showError(Strings.Error.waveFailed(
                    track.url.lastPathComponent, reason: error.localizedDescription))
            }
        }
    }

    /// Тик 10 Гц от движка двигает курсор; подписи времени волна считает сама.
    private func consumePositions() {
        positionsTask?.cancel()
        positionsTask = Task { [weak self] in
            guard let positions = self?.engine.positions else { return }
            for await pos in positions {
                self?.lastElapsed = pos.current
                self?.wave.progress = pos.fraction
            }
        }
    }

    // MARK: - Now Playing

    private func refreshNowPlaying() {
        let url = engine.currentURL
        let track = playlist.model.allTracks.first(where: { $0.url == url })
        guard let track else {
            if engine.state == .idle { nowPlaying.clear() }
            return
        }
        nowPlaying.update(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            elapsed: lastElapsed,
            rate: engine.state == .playing ? 1 : 0,
            artwork: track.artwork
        )
    }

    @objc private func searchChanged() {
        playlist.setQuery(search.stringValue)
    }

    /// Текущий трек для шапки и волны (решение владельца 15:46): пока движок держит трек (играет
    /// или на паузе) - звучащий, без воспроизведения - выделенная строка. Сам выбор - чистая
    /// функция в Core (`PlaylistNavigator.shown`); здесь только подстановка трека из видимого списка.
    private var currentTrack: Track? {
        let playing = engine.state == .idle ? nil : engine.currentURL
        let url = PlaylistNavigator.shown(playing: playing, selected: playlist.selectedTrack?.url)
        return url.flatMap { url in playlist.model.displayed.first { $0.url == url } }
    }

    /// Шапка и волна - на текущем треке. Волна идёт за выделением сразу, не дожидаясь play
    /// (WAVE-ON-SELECT), но во время воспроизведения и паузы текущий - звучащий трек, поэтому
    /// выделение волну не переключает: её курсор и перемотка живут от движка (§6.0b).
    /// Повторный показ того же трека анализ не перезапускает.
    private func showCurrentTrack() {
        refreshChrome()
        guard let track = currentTrack, track.url != waveURL else { return }
        startWave(for: track)
    }

    /// Приоритет статусной строки: свежая ошибка (движок, волна, база) - красным, за ней постоянная
    /// причина, по которой не работают лампочки, и только потом счётчик плейлиста.
    private func refreshChrome() {
        let track = currentTrack
        header.show(track: track)
        if let text = errorText ?? storeFailure {
            statusLabel.stringValue = text
            statusLabel.textColor = Theme.text.danger
        } else if analysisErrors > 0 {
            // Ошибки разбора не прячем: счётчик виден, подробности - в stderr.
            statusLabel.stringValue = Strings.analysisErrors(analysisErrors, summary: playlist.statusText)
            statusLabel.textColor = Theme.text.danger
        } else {
            statusLabel.stringValue = playlist.statusText
            statusLabel.textColor = Theme.text.secondary
        }
    }
}

/// Строка замера отладочного прогона: stderr, чтобы её ловил запуск из скрипта.
func probeReport(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}
