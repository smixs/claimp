import AppKit
import Core

/// Окно настроек (⌘, и пункт «Claimp → Настройки…»).
///
/// Вкладок нет - одна колонка групп (решение владельца 15.09 19:49): Плейлист, Анализ, Волна,
/// Общее. Стиль плоский, как у главного окна: цвета, кегли и размеры - только токены `Theme`.
/// Логики приложения здесь нет: контролы пишут значения в `SettingsStore`, применяют их
/// подписчики нотификации.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private let store: SettingsStore
    private var window: NSWindow?

    /// Контролы держим, чтобы после «Сбросить настройки» показать новые значения без пересборки окна.
    private var columnChecks: [String: NSButton] = [:]
    private let fontSlider = NSSlider()
    private let fontValue = NSTextField(labelWithString: "")
    private let autoAnalyze = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let tempoPopup = NSPopUpButton()
    private let minutesSlider = NSSlider()
    private let minutesValue = NSTextField(labelWithString: "")
    private let keyFormatPopup = NSPopUpButton()
    private let palettePopup = NSPopUpButton()
    private let brightnessSlider = NSSlider()
    private let brightnessValue = NSTextField(labelWithString: "")

    init(store: SettingsStore = .shared) {
        self.store = store
        super.init()
    }

    /// Открыть окно: первый раз собирается, дальше просто выходит вперёд.
    func show() {
        let window = window ?? build()
        self.window = window
        sync()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Сборка

    private func build() -> NSWindow {
        let content = NSView()
        Theme.fill(content, color: Theme.background.base)

        let stack = NSStackView(views: [
            group("Плейлист", rows: playlistRows()),
            group("Анализ", rows: analysisRows()),
            group("Волна", rows: waveRows()),
            group("Общее", rows: [resetRow()]),
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Theme.spacing.xl
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Theme.spacing.l),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Theme.spacing.l),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: Theme.spacing.l),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -Theme.spacing.l),
            content.widthAnchor.constraint(equalToConstant: Theme.size.settingsWidth),
        ])

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Настройки"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.background.base
        window.contentView = content
        window.setContentSize(content.fittingSize)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("ClaimpSettings")
        window.center()
        window.delegate = self
        return window
    }

    private func playlistRows() -> [NSView] {
        let columns = PlaylistColumn.allCases.filter { PlaylistColumns.canHide($0.rawValue) }
        for column in columns {
            let check = NSButton(checkboxWithTitle: column.settingsTitle, target: self, action: #selector(columnToggled))
            check.font = Theme.font.control
            check.identifier = NSUserInterfaceItemIdentifier(column.rawValue)
            tint(check)
            columnChecks[column.rawValue] = check
        }
        // Две колонки чекбоксов: восемь подписей в один столбец растянули бы окно вниз.
        let half = (columns.count + 1) / 2
        let left = column(views: columns.prefix(half).compactMap { columnChecks[$0.rawValue] })
        let right = column(views: columns.suffix(from: half).compactMap { columnChecks[$0.rawValue] })
        let checks = NSStackView(views: [left, right])
        checks.orientation = .horizontal
        checks.alignment = .top
        checks.spacing = Theme.spacing.xl

        fontSlider.target = self
        fontSlider.action = #selector(fontChanged)
        fontSlider.minValue = PlaylistFont.range.lowerBound
        fontSlider.maxValue = PlaylistFont.range.upperBound
        fontSlider.numberOfTickMarks = Int(PlaylistFont.range.upperBound - PlaylistFont.range.lowerBound) + 1
        fontSlider.allowsTickMarkValuesOnly = true
        fontSlider.controlSize = .small
        tint(fontSlider)

        return [
            caption("Видимые колонки. Лампочка «сыграно» видна всегда."),
            checks,
            slider(fontSlider, title: "Размер шрифта", value: fontValue),
        ]
    }

    private func analysisRows() -> [NSView] {
        autoAnalyze.title = "Считать BPM и тональность автоматически"
        autoAnalyze.font = Theme.font.control
        autoAnalyze.target = self
        autoAnalyze.action = #selector(autoAnalyzeToggled)
        tint(autoAnalyze)

        fill(tempoPopup, titles: TempoRangePreset.allCases.map(\.title), action: #selector(tempoChanged))
        fill(keyFormatPopup, titles: KeyFormat.allCases.map(\.title), action: #selector(keyFormatChanged))

        minutesSlider.target = self
        minutesSlider.action = #selector(minutesChanged)
        minutesSlider.minValue = Double(AppSettings.minutesRange.lowerBound)
        minutesSlider.maxValue = Double(AppSettings.minutesRange.upperBound)
        minutesSlider.allowsTickMarkValuesOnly = true
        minutesSlider.numberOfTickMarks =
            AppSettings.minutesRange.upperBound - AppSettings.minutesRange.lowerBound + 1
        minutesSlider.controlSize = .small
        tint(minutesSlider)

        return [
            autoAnalyze,
            labeled("Диапазон BPM", control: tempoPopup),
            slider(minutesSlider, title: "Не считать длиннее", value: minutesValue),
            labeled("Формат тональности", control: keyFormatPopup),
        ]
    }

    private func waveRows() -> [NSView] {
        fill(palettePopup, titles: WavePalette.allCases.map(\.title), action: #selector(paletteChanged))

        brightnessSlider.target = self
        brightnessSlider.action = #selector(brightnessChanged)
        brightnessSlider.minValue = WaveBrightness.range.lowerBound
        brightnessSlider.maxValue = WaveBrightness.range.upperBound
        brightnessSlider.controlSize = .small
        tint(brightnessSlider)

        return [
            labeled("Палитра", control: palettePopup),
            slider(brightnessSlider, title: "Яркость несыгранного", value: brightnessValue),
        ]
    }

    private func resetRow() -> NSView {
        let button = NSButton(title: "Сбросить настройки", target: self, action: #selector(resetTapped))
        button.font = Theme.font.control
        button.bezelStyle = .rounded
        return button
    }

    // MARK: - Кирпичи раскладки

    private func group(_ title: String, rows: [NSView]) -> NSView {
        let header = NSTextField(labelWithString: title.uppercased())
        header.font = Theme.font.section
        header.textColor = Theme.text.secondary
        let stack = NSStackView(views: [header] + rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Theme.spacing.s
        return stack
    }

    private func column(views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = Theme.spacing.xs
        return stack
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = Theme.font.control
        label.textColor = Theme.text.secondary
        return label
    }

    private func labeled(_ title: String, control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = Theme.font.control
        label.textColor = Theme.text.primary
        label.widthAnchor.constraint(equalToConstant: Theme.size.settingsLabel).isActive = true
        let stack = NSStackView(views: [label, control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = Theme.spacing.s
        return stack
    }

    /// Строка со слайдером: подпись, дорожка, текущее значение справа.
    private func slider(_ control: NSSlider, title: String, value: NSTextField) -> NSStackView {
        control.widthAnchor.constraint(equalToConstant: Theme.size.settingsSlider).isActive = true
        value.font = Theme.font.control
        value.textColor = Theme.text.secondary
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: Theme.size.settingsValue).isActive = true
        let row = labeled(title, control: control)
        row.addArrangedSubview(value)
        return row
    }

    /// Системные контролы в теме окна: галочка и заполненная часть дорожки - акцентом Theme,
    /// а не системным синим. Подпись рядом с галочкой остаётся текстовой: `contentTintColor`
    /// красит и её, поэтому цвет подписи задаётся отдельно.
    private func tint(_ control: NSControl) {
        (control as? NSSlider)?.trackFillColor = Theme.accent.violet
        guard let button = control as? NSButton else { return }
        button.contentTintColor = Theme.accent.violet
        button.attributedTitle = NSAttributedString(
            string: button.title,
            attributes: [.font: Theme.font.control, .foregroundColor: Theme.text.primary])
    }

    private func fill(_ popup: NSPopUpButton, titles: [String], action: Selector) {
        popup.removeAllItems()
        popup.addItems(withTitles: titles)
        popup.font = Theme.font.control
        popup.target = self
        popup.action = action
        popup.controlSize = .small
    }

    // MARK: - Значения контролов

    /// Контролы показывают то, что лежит в сторе: и при открытии окна, и после сброса.
    private func sync() {
        let settings = store.value
        for (key, check) in columnChecks {
            check.state = settings.hiddenColumns.contains(key) ? .off : .on
        }
        fontSlider.doubleValue = settings.playlistFontSize
        fontValue.stringValue = "\(Int(settings.playlistFontSize)) pt"
        autoAnalyze.state = settings.autoAnalyze ? .on : .off
        tempoPopup.selectItem(withTitle: settings.tempoRange.title)
        minutesSlider.integerValue = settings.analysisMaxMinutes
        minutesValue.stringValue = "\(settings.analysisMaxMinutes) мин"
        keyFormatPopup.selectItem(withTitle: settings.keyFormat.title)
        palettePopup.selectItem(withTitle: settings.wavePalette.title)
        brightnessSlider.doubleValue = settings.waveUnplayedBrightness
        brightnessValue.stringValue = "\(Int((settings.waveUnplayedBrightness * 100).rounded())) %"
    }

    // MARK: - Действия

    @objc private func columnToggled(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        store.update { settings in
            if sender.state == .on {
                settings.hiddenColumns.remove(key)
            } else {
                settings.hiddenColumns.insert(key)
            }
        }
        sync()
    }

    @objc private func fontChanged(_ sender: NSSlider) {
        store.update { $0.playlistFontSize = sender.doubleValue }
        sync()
    }

    @objc private func autoAnalyzeToggled(_ sender: NSButton) {
        store.update { $0.autoAnalyze = sender.state == .on }
        sync()
    }

    @objc private func tempoChanged(_ sender: NSPopUpButton) {
        guard let preset = TempoRangePreset.allCases.first(where: { $0.title == sender.titleOfSelectedItem })
        else { return }
        store.update { $0.tempoRange = preset }
        sync()
    }

    @objc private func minutesChanged(_ sender: NSSlider) {
        store.update { $0.analysisMaxMinutes = sender.integerValue }
        sync()
    }

    @objc private func keyFormatChanged(_ sender: NSPopUpButton) {
        guard let format = KeyFormat.allCases.first(where: { $0.title == sender.titleOfSelectedItem })
        else { return }
        store.update { $0.keyFormat = format }
        sync()
    }

    @objc private func paletteChanged(_ sender: NSPopUpButton) {
        guard let palette = WavePalette.allCases.first(where: { $0.title == sender.titleOfSelectedItem })
        else { return }
        store.update { $0.wavePalette = palette }
        sync()
    }

    @objc private func brightnessChanged(_ sender: NSSlider) {
        // Шаг слайдера яркости - 5 %: дорожка непрерывная, а значение круглое.
        let stepped = (sender.doubleValue / WaveBrightness.step).rounded() * WaveBrightness.step
        store.update { $0.waveUnplayedBrightness = stepped }
        sync()
    }

    @objc private func resetTapped() {
        store.reset()
        sync()
    }
}

extension PlaylistColumn {
    /// Подпись колонки в настройках: в заголовке таблицы она укорочена до символа.
    var settingsTitle: String {
        switch self {
        case .number: return "# (номер)"
        case .duration: return "Длит."
        case .bitrate: return "kbps"
        default: return headerTitle
        }
    }
}
