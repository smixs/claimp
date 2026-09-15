import AppKit
import QuartzCore

/// Текст, который никогда не расширяет окно, шапку и колонки (SPEC §6.0, решение владельца 14:05).
/// Не влезло - режется по краю контейнера, последние `Theme.size.textFade` уходят в цвет фона;
/// ни многоточия, ни переноса. Ширина своего размера не требует (`noIntrinsicMetric`),
/// сопротивление сжатию низкое - тянется контейнер, а не наоборот.
final class FadingLabel: NSView {
    private let label = NSTextField(labelWithString: "")
    private let fade = CAGradientLayer()

    var stringValue: String {
        get { label.stringValue }
        set {
            label.stringValue = newValue
            invalidateIntrinsicContentSize()
        }
    }

    var font: NSFont? {
        get { label.font }
        set {
            label.font = newValue
            invalidateIntrinsicContentSize()
        }
    }

    var textColor: NSColor? {
        get { label.textColor }
        set { label.textColor = newValue }
    }

    /// Цвет, в который уходит край: фон под текстом (у выделенной строки он другой).
    var fadeColor: NSColor = Theme.background.base {
        didSet { applyFadeColor() }
    }

    /// Гасим только текст, идущий слева направо: в правых колонках (номер, год, длительность)
    /// ширина фиксирована и переполнения не бывает.
    var alignment: NSTextAlignment {
        get { label.alignment }
        set {
            label.alignment = newValue
            fade.isHidden = newValue != .left
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        label.lineBreakMode = .byClipping
        label.usesSingleLineMode = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        applyFadeColor()
        layer?.addSublayer(fade)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Высота своя, ширина - какую дадут: длинный текст не растягивает раскладку.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: label.intrinsicContentSize.height)
    }

    override func layout() {
        super.layout()
        // Накладка всегда поверх текста: слой подвьюхи мог встать выше при пересборке дерева.
        if layer?.sublayers?.last !== fade {
            layer?.addSublayer(fade)
        }
        let width = min(Theme.size.textFade, bounds.width)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = CGRect(x: bounds.maxX - width, y: 0, width: width, height: bounds.height)
        CATransaction.commit()
    }

    private func applyFadeColor() {
        fade.colors = [fadeColor.withAlphaComponent(0).cgColor, fadeColor.cgColor]
    }
}
