import AppKit

/// A volume slider for use as a menu item's view.
@MainActor
final class VolumeSliderView: NSView {
    var onChange: ((Int) -> Void)?

    var level: Int {
        get { Int(slider.doubleValue.rounded()) }
        set { slider.doubleValue = Double(newValue); label.stringValue = "\(newValue)" }
    }

    var muted = false {
        didSet { icon.image = NSImage(systemSymbolName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill", accessibilityDescription: nil) }
    }

    private let icon = NSImageView()
    private let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let label = NSTextField(labelWithString: "–")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 30))
        icon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.isContinuous = true
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right

        let row = NSStackView(views: [icon, slider, label])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            label.widthAnchor.constraint(equalToConstant: 26),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func sliderMoved(_ sender: NSSlider) {
        label.stringValue = "\(level)"
        onChange?(level)
    }
}
