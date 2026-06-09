import AppKit

final class MetricCardView: NSView {
    let titleLabel    = NSTextField(labelWithString: "")
    let gaugeView     = GaugeView()
    let valueLabel    = NSTextField(labelWithString: "--")
    let sparkline     = SparklineView()
    let subtitleLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        titleLabel.alignment = .center

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = .white
        valueLabel.alignment = .center

        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.4)
        subtitleLabel.alignment = .center

        let innerStack = NSStackView(views: [titleLabel, gaugeView, valueLabel, subtitleLabel, sparkline])
        innerStack.orientation = .vertical
        innerStack.spacing = 4
        innerStack.alignment = .centerX
        innerStack.distribution = .fill

        addSubview(innerStack)
        innerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            innerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            innerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            innerStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            innerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            gaugeView.widthAnchor.constraint(equalToConstant: 80),
            gaugeView.heightAnchor.constraint(equalToConstant: 80),
            sparkline.heightAnchor.constraint(equalToConstant: 40),
            sparkline.widthAnchor.constraint(equalTo: innerStack.widthAnchor),
        ])
    }

    func configure(title: String, color: NSColor) {
        titleLabel.stringValue = title
        gaugeView.lineColor = color
        sparkline.lineColor = color
    }
}

extension GaugeView {
    var lineColor: NSColor {
        get { NSColor(cgColor: fillLayer.strokeColor ?? NSColor.green.cgColor) ?? .green }
        set { fillLayer.strokeColor = newValue.cgColor }
    }
}
