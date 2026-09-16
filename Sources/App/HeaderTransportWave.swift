import AppKit
import Core
import Waveform

/// ВЕРХНИЙ БЛОК 164, всё прижато влево: слева квадратная обложка во всю высоту блока
/// минус поля 12; справа от неё сверху три строки (название 17 pt bold, исполнитель 13 pt,
/// техстрока 11 pt), под ними транспорт, сразу за транспортом вертикальная громкость.
/// Свободное место остаётся справа. Нет обложки - пустой слот surface.inset.
final class HeaderView: NSView {
    let transport = TransportView()
    let volume = VolumeControl()

    private let cover = CoverView()
    private let titleLabel = FadingLabel()
    private let artistLabel = FadingLabel()
    private let subtitleLabel = FadingLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Theme.fill(self, color: Theme.background.base)

        Theme.fill(cover, color: Theme.surface.inset, radius: Theme.radius.cover)
        cover.imageScaling = .scaleProportionallyUpOrDown

        for (label, font, color) in [
            (titleLabel, Theme.font.title, Theme.text.primary),
            (artistLabel, Theme.font.artist, Theme.text.secondary),
            (subtitleLabel, Theme.font.tech, Theme.text.secondary),
        ] as [(FadingLabel, NSFont, NSColor)] {
            label.font = font
            label.textColor = color
            label.alignment = .left
        }

        let texts = NSStackView(views: [titleLabel, artistLabel, subtitleLabel])
        texts.orientation = .vertical
        texts.spacing = Theme.spacing.xs
        texts.alignment = .leading

        addSubview(cover)
        addSubview(texts)
        addSubview(transport)
        addSubview(volume)
        for view in [cover, texts, transport, volume] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            // Всё в шапке прижато влево (решение владельца 14:2x): лишнее место остаётся справа,
            // ни центровок, ни привязок к правому краю окна.
            cover.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.spacing.m),
            cover.topAnchor.constraint(equalTo: topAnchor, constant: Theme.spacing.m),
            cover.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.spacing.m),
            cover.widthAnchor.constraint(equalTo: cover.heightAnchor),

            // Каждая строка - во всю ширину колонки текста: длинное название гаснет по краю,
            // а не требует места (NSStackView ширину сам не навязывает).
            titleLabel.widthAnchor.constraint(equalTo: texts.widthAnchor),
            artistLabel.widthAnchor.constraint(equalTo: texts.widthAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: texts.widthAnchor),

            texts.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: Theme.spacing.m),
            texts.topAnchor.constraint(equalTo: cover.topAnchor),
            // Ширина текста ограничена фейдером - только чтобы работал fade.
            texts.trailingAnchor.constraint(equalTo: volume.leadingAnchor, constant: -Theme.spacing.m),

            // Транспорт под текстом, по левому краю текста; ширина - своя, по кнопкам.
            transport.leadingAnchor.constraint(equalTo: texts.leadingAnchor),
            transport.bottomAnchor.constraint(equalTo: cover.bottomAnchor),
            transport.heightAnchor.constraint(equalToConstant: Theme.size.transportStrip),
            transport.topAnchor.constraint(greaterThanOrEqualTo: texts.bottomAnchor, constant: Theme.spacing.s),

            // Фейдер прилеплен к правому краю окна при любой ширине; пустота - между ним и текстом.
            volume.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.spacing.m),
            volume.leadingAnchor.constraint(greaterThanOrEqualTo: transport.trailingAnchor, constant: Theme.spacing.s),
            volume.topAnchor.constraint(equalTo: cover.topAnchor),
            volume.bottomAnchor.constraint(equalTo: cover.bottomAnchor),
            volume.widthAnchor.constraint(equalToConstant: Theme.size.volumeColumn),
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func show(track: Track?) {
        titleLabel.stringValue = track?.title ?? "Claimp"
        artistLabel.stringValue = track?.artist ?? ""
        subtitleLabel.stringValue = track?.headerSubtitle ?? ""
        cover.image = track?.artworkImage
        // Обложку можно утащить в DAW как файл текущего трека (SPEC §6.0b).
        cover.dragFileURL = track?.url
    }
}

/// Обложка в шапке - drag-source файла (SPEC §6.0b): тот же рецепт, что у строки плейлиста
/// и у волны, `.fileURL` + `.copy` наружу; pasteboard-элемент собирает общий помощник волны,
/// чтобы рецепт жил в одном месте. Превью драга - сама обложка в своей рамке.
final class CoverView: NSImageView, NSDraggingSource {
    /// Нет трека - нет и драга: перетаскивать нечего.
    var dragFileURL: URL?

    /// Нужен, чтобы вьюха получила mouseDragged: NSImageView сам жест не ведёт.
    override func mouseDown(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {
        guard let url = dragFileURL else { return }
        let item = NSDraggingItem(pasteboardWriter: WaveformView.pasteboardItem(for: url))
        item.setDraggingFrame(bounds, contents: image ?? NSWorkspace.shared.icon(forFile: url.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }
}

extension Track {
    /// Обложка трека картинкой: одно место разбора `artwork` для шапки и превью драга.
    var artworkImage: NSImage? {
        artwork.flatMap(NSImage.init(data:))
    }
}

/// Кнопка транспорта: только иконка SF Symbols на фоне шапки, без подложки и обводки
/// (решение владельца 14:05). Зона клика - квадрат 44 (play 52), фон прозрачный.
/// Активное состояние (идёт воспроизведение) - иконка accent.violet.
final class TransportIconButton: NSButton {
    private let side: CGFloat
    private let pointSize: CGFloat

    var isActive = false {
        didSet { contentTintColor = isActive ? Theme.accent.violet : Theme.text.primary }
    }

    init(symbol: String, side: CGFloat, pointSize: CGFloat) {
        self.side = side
        self.pointSize = pointSize
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        focusRingType = .none
        contentTintColor = Theme.text.primary
        setSymbol(symbol)
        translatesAutoresizingMaskIntoConstraints = false
        for axis in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            setContentHuggingPriority(.required, for: axis)
            setContentCompressionResistancePriority(.required, for: axis)
        }
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Квадрат и только квадрат: стек не должен растягивать зону клика.
    override var intrinsicContentSize: NSSize {
        NSSize(width: side, height: side)
    }

    func setSymbol(_ symbol: String) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: symbol)?
            .withSymbolConfiguration(config)
    }
}

/// ТРАНСПОРТ 52: ⏮ ⏹ ▶/⏸ ⏭ 🔀 по центру (кнопки 40, play 52).
/// Play и pause - одна кнопка по состоянию движка; громкость - отдельная колонка справа.
final class TransportView: NSView {
    var onPrevious: (() -> Void)?
    var onStop: (() -> Void)?
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onNext: (() -> Void)?
    /// Random переключился: наверх уходит новое состояние режима.
    var onShuffle: ((Bool) -> Void)?

    private let previousButton = TransportIconButton(
        symbol: "backward.end.fill", side: Theme.size.transportButton, pointSize: Theme.size.transportIcon
    )
    private let stopButton = TransportIconButton(
        symbol: "stop.fill", side: Theme.size.transportButton, pointSize: Theme.size.transportIcon
    )
    private let playButton = TransportIconButton(
        symbol: "play.fill", side: Theme.size.playButton, pointSize: Theme.size.playIcon
    )
    private let nextButton = TransportIconButton(
        symbol: "forward.end.fill", side: Theme.size.transportButton, pointSize: Theme.size.transportIcon
    )
    /// Random (решение владельца 16.09): режим случайного следующего трека, рядом с «следующий».
    private let shuffleButton = TransportIconButton(
        symbol: "shuffle", side: Theme.size.transportButton, pointSize: Theme.size.transportIcon
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Theme.fill(self, color: Theme.background.base)

        let center = NSStackView(views: [previousButton, stopButton, playButton, nextButton, shuffleButton])
        center.orientation = .horizontal
        center.spacing = Theme.size.transportGap
        center.alignment = .centerY
        center.distribution = .fill
        addSubview(center)

        for (button, action) in [
            (previousButton, #selector(prevPressed)),
            (stopButton, #selector(stopPressed)),
            (playButton, #selector(playPausePressed)),
            (nextButton, #selector(nextPressed)),
            (shuffleButton, #selector(shufflePressed)),
        ] as [(TransportIconButton, Selector)] {
            button.target = self
            button.action = action
        }

        center.translatesAutoresizingMaskIntoConstraints = false
        // Ряд кнопок задаёт ширину транспорта: вьюха не растягивается и не центруется.
        NSLayoutConstraint.activate([
            center.leadingAnchor.constraint(equalTo: leadingAnchor),
            center.trailingAnchor.constraint(equalTo: trailingAnchor),
            center.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Состояние движка: играет - кнопка показывает паузу и подсвечена акцентом.
    var isPlaying: Bool = false {
        didSet {
            playButton.setSymbol(isPlaying ? "pause.fill" : "play.fill")
            playButton.isActive = isPlaying
        }
    }

    /// Режим Random: включённая кнопка горит акцентом, как играющая кнопка play.
    var isShuffling: Bool = false {
        didSet { shuffleButton.isActive = isShuffling }
    }

    @objc private func prevPressed() { onPrevious?() }
    @objc private func stopPressed() { onStop?() }
    @objc private func playPausePressed() {
        if isPlaying { onPause?() } else { onPlay?() }
    }
    @objc private func nextPressed() { onNext?() }
    @objc private func shufflePressed() {
        isShuffling.toggle()
        onShuffle?(isShuffling)
    }
}
