import ScreenSaver
import AppKit
import Combine

class GPUMonitorSaverView: ScreenSaverView {

    // ── Data ─────────────────────────────────────────────────────────────
    private var monitor: SystemMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var gpuLoad: CGFloat = 0
    private var cpuLoad: CGFloat = 0

    // ── Animated brain ────────────────────────────────────────────────────
    private var brainView: BrainAnimationView?

    // ── Stats overlay (small corner HUD) ─────────────────────────────────
    private var statsLabel: NSTextField?
    private var lastSnapshot: SystemSnapshot = .zero

    // ── Clock ─────────────────────────────────────────────────────────────
    private var lastFrameTime: CFTimeInterval = 0
    private var didSetup = false

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        guard !didSetup, bounds.width > 0 else { return }
        didSetup = true
        buildUI(isPreview: isPreview)
        startMonitor()
    }

    private func buildUI(isPreview: Bool) {
        wantsLayer = true
        // Transparent-ish: very dark overlay so brain pops
        layer?.backgroundColor = NSColor(white: 0, alpha: isPreview ? 0.85 : 0.78).cgColor

        // Brain view – centered, square region
        let brainSize = min(bounds.width, bounds.height) * (isPreview ? 0.72 : 0.58)
        let brain = BrainAnimationView(frame: NSRect(
            x: (bounds.width  - brainSize) / 2,
            y: (bounds.height - brainSize) / 2,
            width: brainSize, height: brainSize
        ))
        brain.wantsLayer = true
        addSubview(brain)
        brainView = brain

        // Stats HUD – bottom-left corner
        let lbl = NSTextField(labelWithString: "")
        lbl.font = .monospacedSystemFont(ofSize: isPreview ? 7 : 13, weight: .medium)
        lbl.textColor = NSColor.white.withAlphaComponent(0.75)
        lbl.backgroundColor = .clear
        lbl.isBordered = false
        lbl.isEditable = false
        lbl.frame = NSRect(x: isPreview ? 4 : 20,
                           y: isPreview ? 4 : 18,
                           width: isPreview ? 120 : 320,
                           height: isPreview ? 60 : 120)
        addSubview(lbl)
        statsLabel = lbl
    }

    private func startMonitor() {
        let m = SystemMonitor()
        monitor = m
        m.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                guard let self else { return }
                self.lastSnapshot  = snap
                self.gpuLoad = CGFloat(snap.gpuUtilization)
                self.cpuLoad = CGFloat(snap.cpuUtilization)
                self.brainView?.gpuLoad = self.gpuLoad
                self.brainView?.cpuLoad = self.cpuLoad
                self.updateStatsLabel(snap)
            }
            .store(in: &cancellables)
    }

    // MARK: - Animation loop

    override func startAnimation() {
        super.startAnimation()
        animationTimeInterval = 1.0 / 60.0
        lastFrameTime = CACurrentMediaTime()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        let dt  = min(CGFloat(now - lastFrameTime), 0.05)
        lastFrameTime = now
        brainView?.advance(by: dt)
    }

    // MARK: - Stats overlay

    private func updateStatsLabel(_ snap: SystemSnapshot) {
        func fmtBytes(_ b: UInt64) -> String {
            let gb = Double(b) / 1_073_741_824
            return gb >= 1 ? String(format: "%.1fG", gb) : String(format: "%.0fM", Double(b)/1_048_576)
        }
        func fmtTemp(_ t: Double?) -> String {
            guard let t else { return " —" }
            return String(format: "%.0f°F", t * 9/5 + 32)
        }

        var lines: [String] = [
            String(format: "GPU  %3d%%   %@", Int(snap.gpuUtilization*100), fmtTemp(snap.gpuTemperature)),
            String(format: "CPU  %3d%%   %@", Int(snap.cpuUtilization*100), fmtTemp(snap.cpuTemperature)),
            String(format: "VRAM %@ / %@", fmtBytes(snap.vramUsed), fmtBytes(snap.vramTotal)),
            String(format: "RAM  %@ / %@", fmtBytes(snap.ramUsed),  fmtBytes(snap.ramTotal)),
        ]
        if !snap.llmModels.isEmpty {
            lines += snap.llmModels.map { "● \($0.name)  [\($0.processor)]" }
        }
        statsLabel?.stringValue = lines.joined(separator: "\n")
    }

    // MARK: - Config sheet

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
