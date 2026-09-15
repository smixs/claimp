import AppKit

/// Фейдер громкости (эталон владельца research/owner-ref-fader-knob.png, DECISIONS 15:34):
/// подпись VOLUME сверху, тонкая вертикальная дорожка, ручка-капсула с тремя чёрточками,
/// проценты снизу. Плоско, без теней; все цвета и размеры - токены Theme.
///
/// Дорожка ниже ручки залита accent.violet (акцент интерфейса; светло-серый эталона
/// в нашей палитре пришёлся бы на запрещённый белый), выше ручки - surface.inset.
final class VolumeSliderCell: NSSliderCell {
    /// Ход ручки должен учитывать её реальную высоту, иначе капсула вылезет за дорожку.
    override var knobThickness: CGFloat {
        Theme.size.volumeKnobHeight
    }

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let thickness = Theme.size.volumeTrack
        let track = NSRect(
            x: rect.midX - thickness / 2, y: rect.minY,
            width: thickness, height: rect.height
        )
        let radius = thickness / 2
        Theme.surface.inset.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        // Заполнение доходит ровно до центра ручки: берём её положение у самой ячейки,
        // чтобы дорожка и капсула не разъезжались на краях хода.
        let knobCenter = knobRect(flipped: flipped).midY
        // Ноль громкости внизу: в перевёрнутых координатах низ дорожки - это maxY.
        let filled = flipped
            ? NSRect(x: track.minX, y: knobCenter, width: thickness, height: track.maxY - knobCenter)
            : NSRect(x: track.minX, y: track.minY, width: thickness, height: knobCenter - track.minY)
        guard filled.height > 0 else { return }
        Theme.accent.violet.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let width = Theme.size.volumeKnobWidth
        let height = Theme.size.volumeKnobHeight
        let knob = NSRect(
            x: knobRect.midX - width / 2, y: knobRect.midY - height / 2,
            width: width, height: height
        )
        let capsule = NSBezierPath(roundedRect: knob, xRadius: width / 2, yRadius: width / 2)
        Theme.surface.raised.setFill()
        capsule.fill()
        capsule.lineWidth = Theme.size.hairline
        Theme.accent.gray.setStroke()
        capsule.stroke()

        // Три горизонтальные чёрточки - «ручка фейдера» с эталона владельца.
        Theme.text.secondary.setFill()
        let gripWidth = width - 2 * Theme.size.volumeGripInset
        let step = Theme.size.volumeGripThickness + Theme.size.volumeGripSpacing
        for offset in -1...1 {
            let grip = NSRect(
                x: knob.midX - gripWidth / 2,
                y: knob.midY + CGFloat(offset) * step - Theme.size.volumeGripThickness / 2,
                width: gripWidth, height: Theme.size.volumeGripThickness
            )
            NSBezierPath(rect: grip).fill()
        }
    }
}

/// Колонка громкости справа в шапке: VOLUME - фейдер - проценты.
///
/// `value` - позиция ручки 0…1, она же то, что видит владелец в процентах.
/// Усиление движка считает `VolumeCurve` в Playback: слайдер линеен по ходу,
/// звук - по децибелам.
final class VolumeControl: NSView {
    var onChange: ((Double) -> Void)?

    /// Позиция ручки 0…1 (не усиление).
    var position: Double {
        get { slider.doubleValue }
        set {
            slider.doubleValue = newValue
            showPercent()
        }
    }

    private let slider = NSSlider()
    private let caption = NSTextField(labelWithString: "VOLUME")
    private let percent = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        Theme.fill(self, color: Theme.background.base)

        slider.cell = VolumeSliderCell()
        slider.isVertical = true
        slider.minValue = 0
        slider.maxValue = 1
        slider.focusRingType = .none
        slider.target = self
        slider.action = #selector(changed)

        for (label, font) in [(caption, Theme.font.micro), (percent, Theme.font.microDigits)] {
            label.font = font
            label.textColor = Theme.text.secondary
            label.alignment = .center
        }
        showPercent()

        for view in [caption, slider, percent] as [NSView] {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: topAnchor),
            slider.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: Theme.spacing.xs),
            percent.topAnchor.constraint(equalTo: slider.bottomAnchor, constant: Theme.spacing.xs),
            percent.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc private func changed() {
        showPercent()
        onChange?(slider.doubleValue)
    }

    private func showPercent() {
        percent.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
    }
}
