import AppKit

final class SparklineView: NSView {
    var values: [Double] = [] {       // 0.0–1.0
        didSet { needsDisplay = true }
    }
    var lineColor: NSColor = NSColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 1)

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true; layer?.backgroundColor = .clear }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard values.count > 1 else { return }

        let b = bounds
        let w = b.width
        let h = b.height
        let step = w / CGFloat(values.count - 1)

        let path = NSBezierPath()
        for (i, v) in values.enumerated() {
            let x = CGFloat(i) * step
            let y = CGFloat(v) * (h - 4) + 2
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else       { path.line(to: CGPoint(x: x, y: y)) }
        }

        // Gradient fill
        let fillPath = path.copy() as! NSBezierPath
        fillPath.line(to: CGPoint(x: w, y: 0))
        fillPath.line(to: CGPoint(x: 0, y: 0))
        fillPath.close()

        NSGraphicsContext.current?.saveGraphicsState()
        fillPath.addClip()
        let gradient = NSGradient(
            colors: [lineColor.withAlphaComponent(0.35), lineColor.withAlphaComponent(0.0)],
            atLocations: [0, 1],
            colorSpace: .deviceRGB
        )
        gradient?.draw(in: b, angle: 90)
        NSGraphicsContext.current?.restoreGraphicsState()

        lineColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
