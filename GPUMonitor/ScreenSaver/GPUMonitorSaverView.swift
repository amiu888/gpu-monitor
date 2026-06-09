import ScreenSaver
import AppKit
import Combine

class GPUMonitorSaverView: ScreenSaverView {

    // ── Data ─────────────────────────────────────────────────────────────
    private var monitor: SystemMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var snap: SystemSnapshot = .zero

    // ── UI layers ─────────────────────────────────────────────────────────
    private var brainView: BrainAnimationView?
    private var llmLabel:  NSTextField?     // big model name
    private var llmSubLabel: NSTextField?   // processor badge
    private var statsRow:  NSView?

    // Individual stat labels (updated each second)
    private var gpuVal, gpuTmp, cpuVal, cpuTmp, vramVal, ramVal: NSTextField?

    private var lastFrameTime: CFTimeInterval = 0
    private var didSetup = false

    // MARK: - Init
    override init?(frame: NSRect, isPreview: Bool) { super.init(frame: frame, isPreview: isPreview) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: - Layout (called once real bounds are known)
    override func layout() {
        super.layout()
        guard !didSetup, bounds.width > 10 else { return }
        didSetup = true
        buildUI()
        startMonitor()
    }

    private func buildUI() {
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.82).cgColor

        let W = bounds.width, H = bounds.height
        let preview = isPreview

        // ── Proportions ────────────────────────────────────────────
        let brainH  = H * (preview ? 0.52 : 0.50)
        let brainW  = brainH   // square
        let brainY  = H - brainH - (preview ? 4 : 20)
        let brainX  = (W - brainW) / 2

        // ── Brain ──────────────────────────────────────────────────
        let brain = BrainAnimationView(frame: NSRect(x: brainX, y: brainY, width: brainW, height: brainH))
        brain.wantsLayer = true
        addSubview(brain)
        brainView = brain

        // ── LLM label block ────────────────────────────────────────
        let llmFontSize: CGFloat = preview ? 11 : min(W / 22, 38)
        let subFontSize: CGFloat = preview ? 8  : min(W / 40, 22)

        let llmName = makeLabel("", size: llmFontSize, weight: .bold,
                                color: NSColor(red:0.3, green:0.9, blue:1, alpha:1))
        llmName.alignment = .center
        llmName.frame = NSRect(x: 20, y: brainY - (preview ? 22 : 62), width: W - 40, height: preview ? 18 : 50)
        addSubview(llmName)
        llmLabel = llmName

        let llmSub = makeLabel("No LLM running", size: subFontSize, weight: .medium,
                               color: NSColor.white.withAlphaComponent(0.4))
        llmSub.alignment = .center
        llmSub.frame = NSRect(x: 20, y: llmName.frame.minY - (preview ? 14 : 34), width: W - 40, height: preview ? 12 : 30)
        addSubview(llmSub)
        llmSubLabel = llmSub

        // ── Stats row ──────────────────────────────────────────────
        let statsH: CGFloat  = preview ? 36 : 90
        let statsY: CGFloat  = preview ? 2  : 18
        let statsView = buildStatsRow(width: W, height: statsH, preview: preview)
        statsView.frame = NSRect(x: 0, y: statsY, width: W, height: statsH)
        addSubview(statsView)
        statsRow = statsView
    }

    // MARK: - Stats row

    private func buildStatsRow(width W: CGFloat, height H: CGFloat, preview: Bool) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))
        container.wantsLayer = true

        // Subtle separator line at top
        let line = NSView(frame: NSRect(x: W*0.05, y: H-1, width: W*0.9, height: 1))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        container.addSubview(line)

        let metrics: [(String, NSColor)] = [
            ("GPU",  NSColor(red:0.2,  green:0.9,  blue:0.5,  alpha:1)),
            ("CPU",  NSColor(red:0.2,  green:0.8,  blue:1.0,  alpha:1)),
            ("VRAM", NSColor(red:0.8,  green:0.4,  blue:1.0,  alpha:1)),
            ("RAM",  NSColor(red:0.3,  green:0.6,  blue:1.0,  alpha:1)),
        ]
        let colW = W / CGFloat(metrics.count)
        let titleSz: CGFloat = preview ? 7  : 13
        let valSz:   CGFloat = preview ? 9  : 20
        let subSz:   CGFloat = preview ? 7  : 12

        var labels: [NSTextField] = []
        for (i, (title, color)) in metrics.enumerated() {
            let cx = CGFloat(i) * colW + colW / 2
            // Title
            let t = makeLabel(title, size: titleSz, weight: .semibold, color: color.withAlphaComponent(0.85))
            t.alignment = .center
            t.frame = NSRect(x: cx - colW/2, y: H - (preview ? 13 : 26), width: colW, height: preview ? 10 : 18)
            container.addSubview(t)
            // Value
            let v = makeLabel("–", size: valSz, weight: .bold, color: .white)
            v.alignment = .center
            v.frame = NSRect(x: cx - colW/2, y: H - (preview ? 26 : 56), width: colW, height: preview ? 14 : 28)
            container.addSubview(v)
            // Sub
            let s = makeLabel("–", size: subSz, weight: .regular, color: NSColor.white.withAlphaComponent(0.45))
            s.alignment = .center
            s.frame = NSRect(x: cx - colW/2, y: H - (preview ? 37 : 78), width: colW, height: preview ? 10 : 20)
            container.addSubview(s)
            labels.append(v)
            labels.append(s)
        }
        // Store refs: GPU val, GPU sub(temp), CPU val, CPU sub(temp), VRAM val, VRAM sub, RAM val, RAM sub
        if labels.count >= 8 {
            gpuVal  = labels[0]; gpuTmp  = labels[1]
            cpuVal  = labels[2]; cpuTmp  = labels[3]
            vramVal = labels[4]; ramVal  = labels[6]
        }
        return container
    }

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = NSFont.systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.isBordered = false
        f.backgroundColor = .clear
        f.isEditable = false
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    // MARK: - Monitor

    private func startMonitor() {
        let m = SystemMonitor()
        monitor = m
        m.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in self?.applySnapshot(s) }
            .store(in: &cancellables)
    }

    private func applySnapshot(_ s: SystemSnapshot) {
        snap = s
        let gpu = CGFloat(s.gpuUtilization)
        let cpu = CGFloat(s.cpuUtilization)
        brainView?.gpuLoad  = gpu
        brainView?.cpuLoad  = cpu

        // Determine LLM processor
        let isGPU = s.llmModels.first?.processor.lowercased().contains("gpu") == true
        let isCPU = s.llmModels.first?.processor.lowercased().contains("cpu") == true
        brainView?.llmOnGPU = isGPU
        brainView?.llmOnCPU = isCPU

        // LLM name block
        if let model = s.llmModels.first {
            llmLabel?.stringValue  = model.name
            let proc = model.processor.isEmpty ? "" : "[\(model.processor)]"
            let size = model.size.isEmpty ? "" : "  \(model.size)"
            llmSubLabel?.stringValue = proc + size
            llmSubLabel?.textColor   = isGPU
                ? NSColor(red:0.2, green:0.9, blue:0.5, alpha:0.9)
                : NSColor(red:0.2, green:0.8, blue:1.0, alpha:0.9)
        } else {
            llmLabel?.stringValue    = ""
            llmSubLabel?.stringValue = "No LLM running"
            llmSubLabel?.textColor   = NSColor.white.withAlphaComponent(0.35)
        }

        // Stats
        func fmtPct(_ v: Double) -> String { "\(Int(v * 100))%" }
        func fmtTmp(_ t: Double?) -> String {
            guard let t else { return "–" }
            return String(format: "%.0f°F", t * 9/5 + 32)
        }
        func fmtBytes(_ b: UInt64) -> String {
            let gb = Double(b) / 1_073_741_824
            return gb >= 1 ? String(format: "%.1fG", gb) : String(format: "%.0fM", Double(b)/1_048_576)
        }

        gpuVal?.stringValue  = fmtPct(s.gpuUtilization)
        gpuTmp?.stringValue  = fmtTmp(s.gpuTemperature)
        cpuVal?.stringValue  = fmtPct(s.cpuUtilization)
        cpuTmp?.stringValue  = fmtTmp(s.cpuTemperature)
        let vf = s.vramTotal > 0 ? Double(s.vramUsed)/Double(s.vramTotal) : 0
        vramVal?.stringValue = fmtBytes(s.vramUsed) + " / " + fmtBytes(s.vramTotal)
        let rf = s.ramTotal > 0 ? Double(s.ramUsed) / Double(s.ramTotal) : 0
        ramVal?.stringValue  = fmtBytes(s.ramUsed)  + " / " + fmtBytes(s.ramTotal)
        _ = vf; _ = rf
    }

    // MARK: - Animation

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

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
