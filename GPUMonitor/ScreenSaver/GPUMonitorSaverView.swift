import ScreenSaver
import AppKit
import Combine

class GPUMonitorSaverView: ScreenSaverView {

    private var monitor: SystemMonitor?
    private var cancellables = Set<AnyCancellable>()
    private var snap: SystemSnapshot = .zero

    private var brainView:    BrainAnimationView?
    private var powerLabel:   NSTextField?   // large "~42W" centre display
    private var llmLabel:     NSTextField?   // model name
    private var llmSubLabel:  NSTextField?   // processor badge
    private var gpuVal, gpuTmp, cpuVal, cpuTmp, vramVal, ramVal: NSTextField?

    private var lastFrameTime: CFTimeInterval = 0
    private var didSetup = false

    override init?(frame: NSRect, isPreview: Bool) { super.init(frame: frame, isPreview: isPreview) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    // MARK: - Layout

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
        let p = isPreview

        // ── Brain (top half) ───────────────────────────────────────────
        let brainH = H * (p ? 0.48 : 0.46)
        let brainW = brainH
        let brainX = (W - brainW) / 2
        let brainY = H * (p ? 0.46 : 0.46)

        let brain = BrainAnimationView(frame: NSRect(x: brainX, y: brainY, width: brainW, height: brainH))
        brain.wantsLayer = true
        addSubview(brain)
        brainView = brain

        // ── Power draw (just below brain centre, very prominent) ───────
        let pwrSz: CGFloat = p ? 16 : min(W / 12, 52)
        let pwrLbl = makeLabel("~– W", size: pwrSz, weight: .heavy,
                               color: NSColor(red:0.3, green:1, blue:0.6, alpha:1))
        pwrLbl.alignment = .center
        let pwrH = pwrSz + 8
        let pwrY = brainY - (p ? pwrH + 4 : pwrH + 10)
        pwrLbl.frame = NSRect(x: W*0.1, y: pwrY, width: W*0.8, height: pwrH)
        addSubview(pwrLbl)
        powerLabel = pwrLbl

        // ── LLM name (large, below power) ─────────────────────────────
        let llmSz: CGFloat = p ? 10 : min(W / 22, 36)
        let llmLbl = makeLabel("", size: llmSz, weight: .bold,
                               color: NSColor(red:0.3, green:0.9, blue:1, alpha:1))
        llmLbl.alignment = .center
        let llmH  = llmSz + 6
        let llmY  = pwrY - (p ? llmH + 2 : llmH + 6)
        llmLbl.frame = NSRect(x: W*0.05, y: llmY, width: W*0.9, height: llmH)
        addSubview(llmLbl)
        llmLabel = llmLbl

        let subSz: CGFloat = p ? 8 : min(W / 40, 20)
        let subLbl = makeLabel("No LLM running", size: subSz, weight: .medium,
                               color: NSColor.white.withAlphaComponent(0.38))
        subLbl.alignment = .center
        let subH = subSz + 4
        let subY = llmY - (p ? subH + 1 : subH + 4)
        subLbl.frame = NSRect(x: W*0.05, y: subY, width: W*0.9, height: subH)
        addSubview(subLbl)
        llmSubLabel = subLbl

        // ── Stats row (bottom) ─────────────────────────────────────────
        let statsH: CGFloat = p ? 38 : 88
        let statsY: CGFloat = p ? 3  : 16
        let row = buildStatsRow(width: W, height: statsH, preview: p)
        row.frame = NSRect(x: 0, y: statsY, width: W, height: statsH)
        addSubview(row)
    }

    // MARK: - Stats row

    private func buildStatsRow(width W: CGFloat, height H: CGFloat, preview p: Bool) -> NSView {
        let v = NSView(frame: .zero); v.wantsLayer = true
        let sep = NSView(); sep.wantsLayer = true
        sep.frame = NSRect(x: W*0.04, y: H-1, width: W*0.92, height: 1)
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        v.addSubview(sep)

        let cols: [(String, NSColor)] = [
            ("GPU",  NSColor(red:0.2,  green:0.9, blue:0.5, alpha:1)),
            ("CPU",  NSColor(red:0.2,  green:0.8, blue:1.0, alpha:1)),
            ("VRAM", NSColor(red:0.8,  green:0.4, blue:1.0, alpha:1)),
            ("RAM",  NSColor(red:0.3,  green:0.6, blue:1.0, alpha:1)),
        ]
        let colW   = W / CGFloat(cols.count)
        let tSz: CGFloat = p ? 7  : 12
        let vSz: CGFloat = p ? 9  : 20
        let sSz: CGFloat = p ? 7  : 11

        var vals: [NSTextField] = []
        for (i, (title, color)) in cols.enumerated() {
            let cx = CGFloat(i) * colW + colW / 2
            let t = makeLabel(title, size: tSz, weight: .semibold, color: color.withAlphaComponent(0.8))
            t.alignment = .center
            t.frame = NSRect(x: cx-colW/2, y: H-(p ? 12:24), width: colW, height: p ? 10:18)
            v.addSubview(t)
            let val = makeLabel("–", size: vSz, weight: .bold, color: .white)
            val.alignment = .center
            val.frame = NSRect(x: cx-colW/2, y: H-(p ? 24:52), width: colW, height: p ? 13:26)
            v.addSubview(val)
            let sub = makeLabel("–", size: sSz, weight: .regular,
                                color: NSColor.white.withAlphaComponent(0.42))
            sub.alignment = .center
            sub.frame = NSRect(x: cx-colW/2, y: H-(p ? 34:72), width: colW, height: p ? 9:18)
            v.addSubview(sub)
            vals.append(val); vals.append(sub)
        }
        if vals.count >= 8 {
            gpuVal  = vals[0]; gpuTmp  = vals[1]
            cpuVal  = vals[2]; cpuTmp  = vals[3]
            vramVal = vals[4]; ramVal  = vals[6]
        }
        return v
    }

    private func makeLabel(_ t: String, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: t)
        f.font = NSFont.systemFont(ofSize: size, weight: weight)
        f.textColor = color
        f.isBordered = false; f.backgroundColor = .clear; f.isEditable = false
        f.lineBreakMode = .byTruncatingTail
        return f
    }

    // MARK: - Monitor

    private func startMonitor() {
        let m = SystemMonitor(); monitor = m
        m.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] s in self?.apply(s) }
            .store(in: &cancellables)
    }

    private func apply(_ s: SystemSnapshot) {
        snap = s
        let gpu = CGFloat(s.gpuUtilization)
        let cpu = CGFloat(s.cpuUtilization)
        brainView?.gpuLoad  = gpu
        brainView?.cpuLoad  = cpu
        let isGPU = s.llmModels.first?.processor.lowercased().contains("gpu") == true
        let isCPU = s.llmModels.first?.processor.lowercased().contains("cpu") == true
        brainView?.llmOnGPU = isGPU
        brainView?.llmOnCPU = isCPU

        // ── Power draw estimate (M4 Max: ~8W idle, up to ~65W peak chip) ──
        let watts = 8 + s.gpuUtilization * 38 + s.cpuUtilization * 20
        powerLabel?.stringValue = String(format: "~%.0f W", watts)

        // ── LLM ──────────────────────────────────────────────────────────
        if let m = s.llmModels.first {
            llmLabel?.stringValue    = m.name
            let proc = m.processor.isEmpty ? "" : "[\(m.processor)]"
            llmSubLabel?.stringValue = [proc, m.size].filter{!$0.isEmpty}.joined(separator: "  ")
            llmSubLabel?.textColor   = isGPU
                ? NSColor(red:0.2, green:0.9, blue:0.5,  alpha:0.9)
                : NSColor(red:0.2, green:0.8, blue:1.0,  alpha:0.9)
        } else {
            llmLabel?.stringValue    = ""
            llmSubLabel?.stringValue = "No LLM running"
            llmSubLabel?.textColor   = NSColor.white.withAlphaComponent(0.32)
        }

        // ── Stats ─────────────────────────────────────────────────────────
        func pct(_ v: Double) -> String { "\(Int(v*100))%" }
        func tmp(_ t: Double?) -> String {
            guard let t else { return "–" }
            return String(format: "%.0f°F", t*9/5+32)
        }
        func bytes(_ b: UInt64) -> String {
            let g = Double(b)/1_073_741_824
            return g >= 1 ? String(format:"%.1fG",g) : String(format:"%.0fM",Double(b)/1_048_576)
        }
        gpuVal?.stringValue  = pct(s.gpuUtilization)
        gpuTmp?.stringValue  = tmp(s.gpuTemperature)
        cpuVal?.stringValue  = pct(s.cpuUtilization)
        cpuTmp?.stringValue  = tmp(s.cpuTemperature)
        vramVal?.stringValue = bytes(s.vramUsed) + " / " + bytes(s.vramTotal)
        ramVal?.stringValue  = bytes(s.ramUsed)  + " / " + bytes(s.ramTotal)
    }

    // MARK: - Animation loop

    override func startAnimation() {
        super.startAnimation()
        animationTimeInterval = 1.0 / 60.0
        lastFrameTime = CACurrentMediaTime()
    }

    override func animateOneFrame() {
        let now = CACurrentMediaTime()
        brainView?.advance(by: min(CGFloat(now - lastFrameTime), 0.05))
        lastFrameTime = now
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
