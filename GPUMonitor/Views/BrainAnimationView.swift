import AppKit

/// Kawaii brain character with:
///   • Neural-node blinking proportional to GPU/CPU load
///   • Running legs+arms animation — speed = GPU %
///   • Sleep state (half-eyes + floating ZZZ) when idle
final class BrainAnimationView: NSView {

    var gpuLoad:  CGFloat = 0
    var cpuLoad:  CGFloat = 0
    var llmOnGPU: Bool    = false
    var llmOnCPU: Bool    = false

    // MARK: - State

    private var t: CGFloat = 0
    private var sleepLevel: CGFloat = 0   // 0=awake, 1=fully asleep (smooth transition)

    // ZZZ particles
    private struct ZZZ {
        var x, y: CGFloat
        var life, maxLife: CGFloat
        var size: CGFloat
        var index: Int          // 0,1,2 → "z","z","Z"
    }
    private var zzzList: [ZZZ] = []
    private var nextZSpawn: CGFloat = 0

    // Brain image (loaded once)
    private lazy var brainImage: NSImage? = {
        // Try bundle first (screen saver), then project path (app)
        if let url = Bundle(for: BrainAnimationView.self)
            .url(forResource: "BrainCharacter", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()

    // ── Node definitions ──────────────────────────────────────────────
    struct Node {
        let x, y, r: CGFloat
        let color: NSColor
        let phase, llmWeight: CGFloat
    }
    private let nodes: [Node] = [
        Node(x:-46, y: 62, r:22, color:NSColor(red:1,   green:0.55,blue:0.72,alpha:1), phase:0.0, llmWeight:1.0),
        Node(x:-14, y: 74, r:24, color:NSColor(red:1,   green:0.58,blue:0.75,alpha:1), phase:0.7, llmWeight:0.8),
        Node(x: 18, y: 72, r:24, color:NSColor(red:1,   green:0.88,blue:0.20,alpha:1), phase:1.4, llmWeight:0.6),
        Node(x: 50, y: 56, r:20, color:NSColor(red:0.55,green:0.75,blue:1.0, alpha:1), phase:2.1, llmWeight:0.4),
        Node(x:-64, y:  4, r:18, color:NSColor(red:0.65,green:0.40,blue:0.90,alpha:1), phase:2.8, llmWeight:0.9),
        Node(x: 62, y:  8, r:18, color:NSColor(red:0.55,green:0.75,blue:1.0, alpha:1), phase:3.5, llmWeight:0.4),
        Node(x:-22, y: -6, r:16, color:NSColor(red:1,   green:0.72,blue:0.82,alpha:1), phase:4.2, llmWeight:0.5),
        Node(x: 24, y: -4, r:16, color:NSColor(red:0.40,green:0.82,blue:0.45,alpha:1), phase:4.9, llmWeight:0.5),
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

        // ZZZ spawning when sleepy
        if sleepLevel > 0.4 {
            nextZSpawn -= dt
            if nextZSpawn <= 0 {
                nextZSpawn = 1.2 - sleepLevel * 0.6
                let idx = zzzList.count % 3
                zzzList.append(ZZZ(
                    x: CGFloat.random(in: 8...28),
                    y: CGFloat.random(in: -5...10),
                    life: 0, maxLife: 2.2,
                    size: 14 + CGFloat(idx) * 6,
                    index: idx
                ))
            }
        }

        // Advance ZZZ
        zzzList = zzzList.compactMap { var z = $0
            z.life += dt
            z.y    += dt * 22
            z.x    += dt * 8
            return z.life < z.maxLife ? z : nil
        }

        needsDisplay = true
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        let unit = min(w, h) / 330.0

        // Bob + sway — minimal at idle, more at high load
        let bobAmp   = unit * (2 + gpuLoad * 9)
        let bobY     = sin(t * 1.4) * bobAmp
        let swayX    = sin(t * 0.9 + 1.2) * unit * gpuLoad * 3.5
        let breath   = 1.0 + sin(t * 1.1) * (0.006 + gpuLoad * 0.010)

        ctx.saveGState()
        ctx.translateBy(x: w / 2 + swayX, y: h / 2 + bobY)
        ctx.scaleBy(x: breath * unit, y: breath * unit)

        drawRunningLegs(ctx)
        drawRunningArms(ctx)
        drawBrainImage(ctx)
        drawNodes(ctx)
        drawEdges(ctx)
        drawSleepOverlay(ctx)
        drawZZZ(ctx)

        ctx.restoreGState()
    }

    // MARK: - Brain image

    private func drawBrainImage(_ ctx: CGContext) {
        guard let img = brainImage else { drawFallbackBrain(ctx); return }
        let size: CGFloat = 300
        let rect = CGRect(x: -size/2, y: -size/2 + 30, width: size, height: size)
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

    // MARK: - Running legs

    private func drawRunningLegs(_ ctx: CGContext) {
        // Running cycle speed scales with GPU load
        let speed   = 2.0 + gpuLoad * 10.0
        let phase   = t * speed
        let maxAngle: CGFloat = .pi * (0.08 + gpuLoad * 0.28)

        let leftAngle  =  sin(phase)        * maxAngle
        let rightAngle = -sin(phase)        * maxAngle
        let liftLeft   = max(0, sin(phase)) * gpuLoad * 12
        let liftRight  = max(0, -sin(phase)) * gpuLoad * 12

        let hipY: CGFloat = -68   // relative to brain centre (inverted: legs go down)
        let legColor = NSColor(red:1, green:0.75, blue:0.82, alpha:1).cgColor
        let footColor = NSColor(red:1, green:0.68, blue:0.78, alpha:1).cgColor

        for (hipX, angle, lift) in [(-20.0, leftAngle, liftLeft),
                                     ( 20.0, rightAngle, liftRight)] as [(CGFloat,CGFloat,CGFloat)] {
            ctx.saveGState()
            ctx.translateBy(x: hipX, y: hipY - lift)
            ctx.rotate(by: angle)

            // Upper leg
            ctx.addPath(roundedRect(x: -11, y: -50, w: 22, h: 50, r: 10))
            ctx.setFillColor(legColor); ctx.fillPath()

            // Foot
            ctx.addEllipse(in: CGRect(x: -14, y: -66, width: 28, height: 18))
            ctx.setFillColor(footColor); ctx.fillPath()

            ctx.restoreGState()
        }
    }

    // MARK: - Running arms

    private func drawRunningArms(_ ctx: CGContext) {
        let speed     = 2.0 + gpuLoad * 10.0
        let phase     = t * speed
        let maxSwing: CGFloat = .pi * (0.06 + gpuLoad * 0.22)

        let leftAngle  = sin(phase)  * maxSwing
        let rightAngle = -sin(phase) * maxSwing

        let shoulderY: CGFloat = 10
        let armColor  = NSColor(red:1, green:0.75, blue:0.82, alpha:1).cgColor
        let handColor = NSColor(red:1, green:0.68, blue:0.78, alpha:1).cgColor

        for (shX, angle) in [(-88.0, leftAngle), (88.0, rightAngle)] as [(CGFloat,CGFloat)] {
            ctx.saveGState()
            ctx.translateBy(x: shX, y: shoulderY)
            ctx.rotate(by: angle)

            // Upper arm
            ctx.addPath(roundedRect(x: shX < 0 ? -36 : 2, y: -14, w: 34, h: 48, r: 14))
            ctx.setFillColor(armColor); ctx.fillPath()

            // Hand
            let hx: CGFloat = shX < 0 ? -22 : 19
            ctx.addEllipse(in: CGRect(x: hx-13, y: 32, width: 26, height: 22))
            ctx.setFillColor(handColor); ctx.fillPath()

            ctx.restoreGState()
        }
    }

    // MARK: - Neural nodes

    private func nodeActivation(_ n: Node) -> CGFloat {
        let spd  = 0.8 + gpuLoad * 2.5
        let base = (sin(t * spd * .pi + n.phase) + 1) / 2
        let llm  = (llmOnGPU || llmOnCPU) ? n.llmWeight * 0.45 : 0
        let cpu  = cpuLoad * (n.phase > 2.5 && n.phase < 4 ? 0.28 : 0.05)
        let gpu  = gpuLoad * (n.phase < 2.5 ? 0.32 : 0.08)
        return min(1, base * (0.35 + gpuLoad * 0.45) + llm + cpu + gpu)
    }

    private func drawEdges(_ ctx: CGContext) {
        for (i, j) in edges {
            let a = nodeActivation(nodes[i])
            let b = nodeActivation(nodes[j])
            let v = (a + b) / 2
            guard v > 0.28 else { continue }
            ctx.setStrokeColor(NSColor.white.withAlphaComponent((v-0.28)/0.72 * 0.65).cgColor)
            ctx.setLineWidth(0.7 + v * 1.4)
            ctx.move(to: CGPoint(x: nodes[i].x, y: nodes[i].y + 30))
            ctx.addLine(to: CGPoint(x: nodes[j].x, y: nodes[j].y + 30))
            ctx.strokePath()
        }
    }

    private func drawNodes(_ ctx: CGContext) {
        for n in nodes {
            let act = nodeActivation(n)
            guard act > 0.06 else { continue }
            let ny = n.y + 30
            let gr = n.r * (1 + act * 0.8)
            ctx.addEllipse(in: CGRect(x: n.x-gr, y: ny-gr, width: gr*2, height: gr*2))
            ctx.setFillColor(n.color.withAlphaComponent(act * 0.32).cgColor); ctx.fillPath()
            let cr = n.r * 0.36 * (0.6 + act * 0.7)
            ctx.addEllipse(in: CGRect(x: n.x-cr, y: ny-cr, width: cr*2, height: cr*2))
            ctx.setFillColor(n.color.withAlphaComponent(0.5 + act * 0.5).cgColor); ctx.fillPath()
        }
    }

    // MARK: - Sleep overlay (half-closed eyes)

    private func drawSleepOverlay(_ ctx: CGContext) {
        guard sleepLevel > 0.1 else { return }
        let a = sleepLevel
        // Droop eyelids over the eyes
        // Eye positions relative to brain centre: left=(-32, -10+30)=(-32,20), right=(32,20)
        for ex: CGFloat in [-32, 32] {
            let ey: CGFloat = 20    // eye Y in brain coords (with +30 offset)
            // Lid that covers top half of eye
            let lidH = 22.0 * (0.3 + a * 0.65)
            ctx.addEllipse(in: CGRect(x: ex-22, y: ey-2, width: 44, height: lidH * 2))
            ctx.setFillColor(NSColor(red:1, green:0.75, blue:0.82, alpha: a * 0.95).cgColor)
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
            ctx.translateBy(x: z.x + 60, y: z.y + 130)
            ctx.scaleBy(x: scale, y: scale)

            let str = letters[z.index] as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: z.size, weight: .bold),
                .foregroundColor: NSColor(red: 0.7, green: 0.85, blue: 1, alpha: alpha * sleepLevel)
            ]
            str.draw(at: CGPoint(x: 0, y: 0), withAttributes: attrs)
            ctx.restoreGState()
        }
    }

    // MARK: - Helpers

    private func roundedRect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h),
                            cornerWidth: r, cornerHeight: r)
        return path
    }
}
