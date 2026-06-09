import ScreenSaver
import AppKit

class GPUMonitorSaverView: ScreenSaverView {
    private var dashVC: DashboardViewController?
    private var didSetup = false

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // Layout is called once the view has its real size
    override func layout() {
        super.layout()
        guard !didSetup, bounds.width > 0, bounds.height > 0 else { return }
        didSetup = true
        buildDashboard(isPreview: isPreview)
    }

    private func buildDashboard(isPreview: Bool) {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let nativeW: CGFloat = 680, nativeH: CGFloat = 280
        let scale: CGFloat
        if isPreview {
            scale = min(bounds.width / nativeW, bounds.height / nativeH) * 0.90
        } else {
            scale = min(bounds.height * 0.50 / nativeH, bounds.width * 0.82 / nativeW)
        }
        let w = floor(nativeW * scale), h = floor(nativeH * scale)

        let container = NSView(frame: NSRect(
            x: floor((bounds.width  - w) / 2),
            y: floor((bounds.height - h) / 2),
            width: w, height: h
        ))
        container.wantsLayer = true
        container.layer?.cornerRadius = isPreview ? 8 : 20
        container.layer?.backgroundColor = NSColor(white: 0.07, alpha: 0.97).cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        addSubview(container)

        let vc = DashboardViewController()
        dashVC = vc
        vc.view.frame = container.bounds
        vc.view.autoresizingMask = [.width, .height]
        container.addSubview(vc.view)
    }

    override func startAnimation() {
        super.startAnimation()
        animationTimeInterval = 1.0
    }

    override func animateOneFrame() {
        // SystemMonitor's Timer drives data updates; nothing per-frame
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
