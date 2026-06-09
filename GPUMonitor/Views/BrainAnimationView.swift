import AppKit

/// Kawaii brain character animation using the original image.
/// • Image rendered as-is (already has arms, legs, face)
/// • Bob / sway / scale — proportional to GPU load (simulates running)
/// • Neural-node glow overlay — pulses with GPU/CPU activity
/// • Sleep state — gentle droop overlay + floating ZZZ when idle
final class BrainAnimationView: NSView {

    var gpuLoad:  CGFloat = 0
    var cpuLoad:  CGFloat = 0
    var llmOnGPU: Bool    = false
    var llmOnCPU: Bool    = false

    // MARK: - State

    private var t: CGFloat = 0
    private var sleepLevel: CGFloat = 0   // 0=awake, 1=fully asleep

    // ZZZ particles
    private struct ZZZ {
        var x, y: CGFloat
        var life, maxLife: CGFloat
        var size: CGFloat
        var index: Int          // 0,1,2 → "z","z","Z"
    }
    private var zzzList: [ZZZ] = []
    private var nextZSpawn: CGFloat = 0

    // Brain image (the original, loaded once)
    private lazy var brainImage: NSImage? = {
        if let url = Bundle(for: BrainAnimationView.self)
            .url(forResource: "BrainCharacter", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()

    // ── Neural nodes (overlay glow on the brain lobes) ────────────────
    struct Node {
        let x, y, r: CGFloat          // relative to character centre
        let color: NSColor
        let phase, llmWeight: CGFloat
    }
    // Positions matched to the coloured lobes in the image
    private let nodes: [Node] = [
        Node(x:-55, y: 55, r:28, color:NSColor(red:1,   green:0.55,blue:0.72,alpha:1), phase:0.0, llmWeight:1.0),
        Node(x:-15, y: 68, r:26, color:NSColor(red:1,   green:0.58,blue:0.75,alpha:1), phase:0.7, llmWeight:0.8),
        Node(x: 22, y: 68, r:26, color:NSColor(red:1,   green:0.88,blue:0.20,alpha:1), phase:1.4, llmWeight:0.6),
        Node(x: 60, y: 50, r:24, color:NSColor(red:0.55,green:0.75,blue:1.0, alpha:1), phase:2.1, llmWeight:0.4),
        Node(x:-75, y:  2, r:20, color:NSColor(red:0.65,green:0.40,blue:0.90,alpha:1), phase:2.8, llmWeight:0.9),
        Node(x: 72, y:  6, r:20, color:NSColor(red:0.55,green:0.75,blue:1.0, alpha:1), phase:3.5, llmWeight:0.4),
        Node(x:-25, y: -8, r:18, color:NSColor(red:1,   green:0.72,blue:0.82,alpha:1), phase:4.2, llmWeight:0.5),
        Node(x: 28, y: -4, r:18, color:NSColor(red:0.40,green:0.82,blue:0.45,alpha:1), phase:4.9, llmWeight:0.5),
    ]
    private let edges: [(Int,Int)] = [
        (0,1),(1,2),(2,3),(0,4),(3,5),(4,6),(5,7),(6,7),(1,4),(2,5)
    ]

    override var isFlipped: Bool { false }

    // MARK: - Tick

    func advance(by dt: CGFloat) {
        t += dt
        let activity = (gpuLoad + cpuLoad) / 2

        // Smooth sleep transition
        let targetSleep: CGFloat = activity < 0.05 ? 1 : 0
        let sleepSpeed: CGFloat  = targetSleep > sleepLevel ? 0.3 : 0.8
        sleepLevel += (targetSleep - sleepLevel) * dt * sleepSpeed

        // ZZZ spawning
        if sleepLevel > 0.4 {
            nextZSpawn -= dt
            if nextZSpawn <= 0 {
                nextZSpawn = 1.2 - sleepLevel * 0.6
                let idx = zzzList.count % 3
                zzzList.append(ZZZ(
                    x: CGFloat.random(in: 8...30),
                    y: CGFloat.random(in: -5...10),
                    life: 0, maxLife: 2.4,
                    size: 14 + CGFloat(idx) * 6,
                    index: idx
                ))
            }
        }

        // Advance ZZZ
        zzzList = zzzList.compactMap { var z = $0
            z.life += dt
            z.y    += dt * 20
            z.x    += dt * 7
            return z.life < z.maxLife ? z : nil
        }

        needsDisplay = true
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        let unit = min(w, h) / 340.0

        // Running-style bob + sway — amplitude scales with GPU load
        let speed    = 1.0 + gpuLoad * 5.0          // faster "running" at high GPU
        let bobAmp   = unit * (1.5 + gpuLoad * 10.0)
        let bobY     = sin(t * speed * 2.0) * bobAmp
        let swayX    = sin(t * speed * 0.9 + 1.2) * unit * gpuLoad * 5.0
        let tilt     = sin(t * speed * 2.0 + 0.3) * gpuLoad * 0.04  // subtle rotation
        let breath   = 1.0 + sin(t * 1.1) * (0.005 + gpuLoad * 0.008)
        let scale    = breath * unit

        ctx.saveGState()
        ctx.translateBy(x: w / 2 + swayX, y: h / 2 + bobY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.rotate(by: tilt)

        drawBrainImage(ctx)
        drawNodes(ctx)
        drawEdges(ctx)
        drawSleepOverlay(ctx)
        drawZZZ(ctx)

        ctx.restoreGState()
    }

    // MARK: - Brain image (original, no modifications)

    private func drawBrainImage(_ ctx: CGContext) {
        guard let img = brainImage else { drawFallbackBrain(ctx); return }
        // Image is 800x800 with transparent background
        // Draw it centred; the character occupies roughly 85% of the canvas
        let size: CGFloat = 320
        let rect = CGRect(x: -size/2, y: -size/2 - 20, width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        img.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFallbackBrain(_ ctx: CGContext) {
        ctx.addEllipse(in: CGRect(x: -90, y: -60, width: 180, height: 155))
        ctx.setFillColor(NSColor(red:1, green:0.75, blue:0.82, alpha:1).cgColor)
        ctx.fillPath()
    }

    // MARK: - Neural node glow

    private func nodeActivation(_ n: Node) -> CGFloat {
        let spd  = 0.8 + gpuLoad * 2.5
        let base = (sin(t * spd * .pi + n.phase) + 1) / 2
        let llm  = (llmOnGPU || llmOnCPU) ? n.llmWeight * 0.45 : 0
        let cpu  = cpuLoad * (n.phase > 2.5 && n.phase < 4 ? 0.28 : 0.05)
        let gpu  = gpuLoad * (n.phase < 2.5 ? 0.32 : 0.08)
        return min(1, base * (0.30 + gpuLoad * 0.45) + llm + cpu + gpu)
    }

    private func drawEdges(_ ctx: CGContext) {
        for (i, j) in edges {
            let a = nodeActivation(nodes[i])
            let b = nodeActivation(nodes[j])
            let v = (a + b) / 2
            guard v > 0.28 else { continue }
            ctx.setStrokeColor(NSColor.white.withAlphaComponent((v-0.28)/0.72 * 0.55).cgColor)
            ctx.setLineWidth(0.6 + v * 1.2)
            // Offset nodes to align with lobe centres in the image
            ctx.move(to:    CGPoint(x: nodes[i].x, y: nodes[i].y + 40))
            ctx.addLine(to: CGPoint(x: nodes[j].x, y: nodes[j].y + 40))
            ctx.strokePath()
        }
    }

    private func drawNodes(_ ctx: CGContext) {
        for n in nodes {
            let act = nodeActivation(n)
            guard act > 0.06 else { continue }
            let ny  = n.y + 40
            let gr  = n.r * (1 + act * 0.9)
            // Outer glow
            ctx.addEllipse(in: CGRect(x: n.x-gr, y: ny-gr, width: gr*2, height: gr*2))
            ctx.setFillColor(n.color.withAlphaComponent(act * 0.28).cgColor); ctx.fillPath()
            // Core dot
            let cr = n.r * 0.32 * (0.6 + act * 0.7)
            ctx.addEllipse(in: CGRect(x: n.x-cr, y: ny-cr, width: cr*2, height: cr*2))
            ctx.setFillColor(n.color.withAlphaComponent(0.45 + act * 0.55).cgColor); ctx.fillPath()
        }
    }

    // MARK: - Sleep overlay (drooping eyelids)

    private func drawSleepOverlay(_ ctx: CGContext) {
        guard sleepLevel > 0.1 else { return }
        let a = sleepLevel
        // Eye positions relative to brain centre (image-matched)
        for ex: CGFloat in [-30, 32] {
            let ey: CGFloat = 28
            let lidH = 20.0 * (0.3 + a * 0.65)
            ctx.addEllipse(in: CGRect(x: ex-20, y: ey - 2, width: 40, height: lidH * 2))
            ctx.setFillColor(NSColor(red:1, green:0.75, blue:0.82, alpha: a * 0.93).cgColor)
            ctx.fillPath()
        }
    }

    // MARK: - ZZZ

    private func drawZZZ(_ ctx: CGContext) {
        guard !zzzList.isEmpty else { return }
        let letters = ["z", "z", "Z"]
        for z in zzzList {
            let progress = z.life / z.maxLife
            let alpha    = progress < 0.15 ? progress / 0.15
                         : progress > 0.75 ? (1 - progress) / 0.25
                         : 1.0
            let scale    = 0.7 + progress * 0.5

            ctx.saveGState()
            ctx.translateBy(x: z.x + 55, y: z.y + 130)
            ctx.scaleBy(x: scale, y: scale)

            let str = letters[z.index] as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: z.size, weight: .bold),
                .foregroundColor: NSColor(red: 0.7, green: 0.85, blue: 1, alpha: alpha * sleepLevel)
            ]
            str.draw(at: .zero, withAttributes: attrs)
            ctx.restoreGState()
        }
    }
}
