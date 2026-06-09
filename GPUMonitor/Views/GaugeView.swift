import AppKit
import QuartzCore

final class GaugeView: NSView {
    var value: Double = 0 {        // 0.0–1.0
        didSet { animate(to: value) }
    }
    var dangerThreshold: Double = 0.85
    var label: String = "" {
        didSet { textLayer.string = label }
    }

    private let trackLayer = CAShapeLayer()
    let fillLayer  = CAShapeLayer()
    private let textLayer  = CATextLayer()

    // Temperature mode: value represents °C, max is 100°C
    var isTemperatureGauge = false
    var maxTemperature: Double = 100

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }

    private func setup() {
        wantsLayer = true

        // Track arc
        trackLayer.strokeColor = NSColor.white.withAlphaComponent(0.12).cgColor
        trackLayer.fillColor = NSColor.clear.cgColor
        trackLayer.lineWidth = 6
        trackLayer.lineCap = .round

        // Fill arc
        fillLayer.fillColor = NSColor.clear.cgColor
        fillLayer.lineWidth = 6
        fillLayer.lineCap = .round
        fillLayer.strokeEnd = 0

        // Value label
        textLayer.alignmentMode = .center
        textLayer.fontSize = 12
        textLayer.foregroundColor = NSColor.white.withAlphaComponent(0.9).cgColor
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2

        layer?.addSublayer(trackLayer)
        layer?.addSublayer(fillLayer)
        layer?.addSublayer(textLayer)
    }

    override func layout() {
        super.layout()
        let b = bounds
        let center = CGPoint(x: b.midX, y: b.midY)
        let radius = min(b.width, b.height) / 2 - 8

        let startAngle = CGFloat.pi * 0.75       // lower-left
        let endAngle   = CGFloat.pi * 2.25       // lower-right (full sweep = 270°)

        let arc = CGMutablePath()
        arc.addArc(center: center, radius: radius,
                   startAngle: startAngle, endAngle: endAngle, clockwise: false)
        let arcPath = arc

        trackLayer.path = arcPath
        fillLayer.path  = arcPath
        fillLayer.frame = b

        // Text label frame (center)
        let tw: CGFloat = b.width * 0.8
        let th: CGFloat = 16
        textLayer.frame = CGRect(
            x: b.midX - tw/2,
            y: b.midY - th/2,
            width: tw, height: th
        )
    }

    private func animate(to newValue: Double) {
        let clamped = max(0, min(1, newValue))
        let anim = CABasicAnimation(keyPath: "strokeEnd")
        anim.fromValue = fillLayer.presentation()?.strokeEnd ?? fillLayer.strokeEnd
        anim.toValue   = clamped
        anim.duration  = 0.3
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        fillLayer.strokeEnd = CGFloat(clamped)
        fillLayer.add(anim, forKey: "strokeEnd")
        fillLayer.strokeColor = color(for: newValue).cgColor
    }

    private func color(for v: Double) -> NSColor {
        if v >= dangerThreshold { return .systemRed }
        if v >= dangerThreshold * 0.75 { return .systemOrange }
        return NSColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 1)  // green
    }
}
