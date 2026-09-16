import AppKit
import Core
import Foundation

/// Волна трека: симметричные столбики от центральной оси, цвет каждого - смесь трёх полос.
/// Сыгранная часть ярче несыгранной, курсор на границе, подписи времени под волной.
/// Клик и драг мышью отдают долю трека в `onSeek`: волна - только перемотка, drag файла с неё
/// отменён (решение владельца 15:36); файл тащат за строку плейлиста и за обложку в шапке.
@MainActor
public final class WaveformView: NSView {
    /// Полоса с подписями времени под волной; сами числа - в `WaveformStyle.Geometry`.
    public static var timeStripHeight: CGFloat { WaveformStyle.Geometry.timeStripHeight }

    /// Высота самой волны по проценту из настроек (⌘, → Волна); процент вне 20…100
    /// прижимается к границе.
    public static func waveHeight(percent: Int) -> CGFloat {
        WaveformStyle.Geometry.maxWaveHeight * CGFloat(WaveHeight.clamp(percent))
            / CGFloat(WaveHeight.range.upperBound)
    }

    /// Высота всего блока: волна плюс полоса времени под ней.
    public static func blockHeight(percent: Int) -> CGFloat {
        waveHeight(percent: percent) + timeStripHeight
    }

    /// Стиль волны: цвета полос, компрессия, сглаживание, яркости, курсор. Все числа - только здесь
    /// и в дефолте `WaveformStyle`: в отрисовке литералов нет.
    public var style: WaveformStyle = .default {
        didSet {
            guard style != oldValue else { return }
            rebuildWaveform()
        }
    }

    /// Волна текущего трека. `nil` - данных ещё нет: полоса показывает тонкую осевую линию
    /// по центру, пока идёт анализ (SPEC §6.12).
    public var data: WaveformData? {
        didSet {
            bands = Self.bands(from: data)
            rebuildWaveform()
        }
    }

    /// Доля сыгранного, 0…1. Значения вне диапазона и NaN прижимаются к краям.
    public var progress: Double {
        get { clampedProgress }
        set {
            let clamped = Self.clamp(newValue)
            guard clamped != clampedProgress else { return }
            clampedProgress = clamped
            updateProgress()
        }
    }

    /// Длина трека для правой подписи; 0 - подписи пустые.
    public var duration: TimeInterval = 0 {
        didSet { updateTimeLabels() }
    }

    /// Клик и горизонтальный драг по волне: доля трека 0…1.
    public var onSeek: ((Double) -> Void)?

    private var clampedProgress: Double = 0
    private var bands: (low: [Float], mid: [Float], high: [Float]) = ([], [], [])
    private var renderedSize: CGSize = .zero

    private let waveLayer = CALayer()
    private let unplayedLayer = CALayer()
    private let cursorLayer = CALayer()
    private let elapsedLabel = NSTextField(labelWithString: "")
    private let totalLabel = NSTextField(labelWithString: "")

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.blockHeight(percent: WaveHeight.default))
    }

    public override var isOpaque: Bool { true }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        rebuildWaveform()
    }

    public override func layout() {
        super.layout()
        layoutLabels()
        if bounds.size != renderedSize {
            rebuildWaveform()
        }
    }

    // MARK: - Мышь

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        seek(to: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        seek(to: event)
    }

    private func seek(to event: NSEvent) {
        guard bounds.width > 0 else { return }
        let location = convert(event.locationInWindow, from: nil)
        let fraction = Self.clamp(Double(location.x / bounds.width))
        progress = fraction
        onSeek?(fraction)
    }

    // MARK: - Отрисовка

    private func setUp() {
        wantsLayer = true
        for layer in [waveLayer, unplayedLayer, cursorLayer] {
            layer.contentsScale = window?.backingScaleFactor ?? 2
        }
        layer?.addSublayer(waveLayer)
        layer?.addSublayer(unplayedLayer)
        layer?.addSublayer(cursorLayer)

        for label in [elapsedLabel, totalLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            // Подписи времени - не про волну: палитры в WaveformStyle у них нет, берём системный цвет.
            label.textColor = .secondaryLabelColor
            label.backgroundColor = .clear
            label.isBordered = false
            label.isSelectable = false
            addSubview(label)
        }
        totalLabel.alignment = .right
        applyStyle()
        updateTimeLabels()
    }

    private var waveRect: CGRect {
        CGRect(x: 0, y: Self.timeStripHeight, width: bounds.width,
               height: max(0, bounds.height - Self.timeStripHeight))
    }

    /// Пересчёт под текущий размер: данные трека не трогаются, ресайз окна анализа не вызывает.
    private func rebuildWaveform() {
        renderedSize = bounds.size
        applyStyle()
        let rect = waveRect
        guard rect.width >= 1, rect.height >= 1 else {
            waveLayer.contents = nil
            return
        }
        let backing = convertToBacking(rect)
        let pixelWidth = max(1, Int(backing.width.rounded()))
        let pixelHeight = max(1, Int(backing.height.rounded()))
        for layer in [waveLayer, cursorLayer, unplayedLayer] {
            layer.contentsScale = window?.backingScaleFactor ?? 2
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        waveLayer.frame = rect
        waveLayer.contents = makeWaveImage(width: pixelWidth, height: pixelHeight)
        CATransaction.commit()
        updateProgress()
    }

    /// Битмап волны: по столбику на пиксель бэкинга, поэтому у каждого своя смесь цветов.
    /// Перестраивается только при смене данных, стиля или размера - не на каждый тик прогресса.
    /// Метод не `private`: это шов для теста пустого состояния.
    func makeWaveImage(width: Int, height: Int) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Поле и минимум заданы в точках, поэтому переводятся в пиксели масштабом высоты.
        let scale = CGFloat(height) / max(waveRect.height, 1)
        let profile = WaveformProfile.make(
            low: bands.low, mid: bands.mid, high: bands.high, width: width, style: style)
        // Пустое состояние (SPEC §6.12): пока данных нет, по центру идёт тонкая осевая линия,
        // а не ровный фон. Толщина - minimumBarHeight, цвет - emptyLine.
        guard !profile.heights.isEmpty else {
            let lineHeight = max((style.minimumBarHeight * scale).rounded(), 1)
            context.setFillColor(style.emptyLine.cgColor())
            context.fill(CGRect(
                x: 0, y: ((CGFloat(height) - lineHeight) / 2).rounded(),
                width: CGFloat(width), height: lineHeight))
            return context.makeImage()
        }

        // Высота симметрична от центра, поле не даёт упереться в край,
        // минимум оставляет тишине тонкую линию. Ширина столбика - ровно один пиксель.
        let halfHeight = CGFloat(height) / 2
        let inset = style.verticalInset * scale
        let minimum = style.minimumBarHeight * scale
        context.setShouldAntialias(false)
        for index in 0..<profile.heights.count {
            let amplitude = CGFloat(profile.heights[index]) * max(0, halfHeight - inset)
            let barHeight = max(minimum, 2 * amplitude)
            let originY = ((CGFloat(height) - barHeight) / 2).rounded()
            context.setFillColor(profile.colors[index].cgColor(brightness: style.playedBrightness))
            context.fill(CGRect(x: CGFloat(index), y: originY, width: 1, height: barHeight))
        }
        return context.makeImage()
    }

    /// Фон, приглушение несыгранного и цвет курсора: всё из `WaveformStyle`.
    private func applyStyle() {
        layer?.backgroundColor = style.background.cgColor()
        unplayedLayer.backgroundColor = style.background.cgColor(alpha: unplayedAlpha)
        cursorLayer.backgroundColor = style.cursor.cgColor()
    }

    /// Альфа слоя приглушения: сыгранное остаётся на `playedBrightness`, несыгранное - на `unplayedBrightness`.
    private var unplayedAlpha: Double {
        let played = max(style.playedBrightness, 0.0001)
        return min(max(1 - style.unplayedBrightness / played, 0), 1)
    }

    private func updateProgress() {
        let rect = waveRect
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let playedWidth = rect.width * CGFloat(clampedProgress)
        unplayedLayer.frame = CGRect(
            x: playedWidth, y: rect.minY, width: max(0, rect.width - playedWidth), height: rect.height)
        let cursorWidth = max(style.cursorWidth, 0)
        let cursorX = min(max(0, playedWidth - cursorWidth / 2), max(0, rect.width - cursorWidth))
        cursorLayer.frame = CGRect(x: cursorX, y: rect.minY, width: cursorWidth, height: rect.height)
        cursorLayer.isHidden = rect.width < 1 || cursorWidth <= 0
        CATransaction.commit()
        updateTimeLabels()
    }

    private func layoutLabels() {
        let height = Self.timeStripHeight
        let width = max(0, bounds.width / 2 - 8)
        elapsedLabel.frame = CGRect(x: 4, y: 0, width: width, height: height)
        totalLabel.frame = CGRect(x: bounds.width - width - 4, y: 0, width: width, height: height)
    }

    private func updateTimeLabels() {
        guard duration > 0 else {
            elapsedLabel.stringValue = ""
            totalLabel.stringValue = ""
            return
        }
        elapsedLabel.stringValue = Self.timeLabel(duration * clampedProgress)
        totalLabel.stringValue = Self.timeLabel(duration)
    }

    private static func bands(from data: WaveformData?) -> (low: [Float], mid: [Float], high: [Float]) {
        guard let columns = data?.columns else { return ([], [], []) }
        return (columns.map(\.low), columns.map(\.mid), columns.map(\.high))
    }

    /// Прогресс всегда в 0…1; NaN считаем нулём, чтобы не ронять геометрию слоёв.
    nonisolated static func clamp(_ progress: Double) -> Double {
        guard !progress.isNaN else { return 0 }
        return min(max(progress, 0), 1)
    }

    /// `8:21` для коротких треков, `1:02:09` для длинных.
    nonisolated static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds.isNaN ? 0 : seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

private extension WaveformStyle.Color {
    /// Цвет в sRGB с яркостью `brightness` (0…1) и альфой: NSColor в отрисовке не участвует.
    func cgColor(brightness: Double = 1, alpha: Double = 1) -> CGColor {
        CGColor(
            srgbRed: red * min(max(brightness, 0), 1),
            green: green * min(max(brightness, 0), 1),
            blue: blue * min(max(brightness, 0), 1),
            alpha: min(max(alpha, 0), 1))
    }
}
