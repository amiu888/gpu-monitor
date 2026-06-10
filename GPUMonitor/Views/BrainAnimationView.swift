import AppKit

/// Kawaii brain character with:
///   • Original image (transparent PNG, all limbs intact)
///   • Neural-node glow on each lobe, proportional to GPU/CPU load
///   • 7 floating labels matching the original diagram, mapped to LLM pipeline steps
///   • Labels grow / pulse when GPU is working hard
///   • LLM pipeline flow animation: lobes light up in sequence when LLM is running
///   • Running bob/sway animation — speed ∝ GPU%
///   • Sleep (ZZZ) when idle
final class BrainAnimationView: NSView {

    // MARK: - Public inputs
    var gpuLoad:  CGFloat = 0
    var cpuLoad:  CGFloat = 0
    var llmOnGPU: Bool    = false
    var llmOnCPU: Bool    = false

    // MARK: - State
    private var t: CGFloat = 0
    private var sleepLevel: CGFloat = 0
    private var pipelinePhase: CGFloat = 0   // 0-1 cycles through pipeline steps

    // ZZZ particles
    private struct ZZZ {
        var x, y, life, maxLife, size: CGFloat
        var index: Int
    }
    private var zzzList: [ZZZ] = []
    private var nextZSpawn: CGFloat = 0

    // Brain image
    private lazy var brainImage: NSImage? = {
        if let url = Bundle(for: BrainAnimationView.self)
            .url(forResource: "BrainCharacter", withExtension: "png") {
            return NSImage(contentsOf: url)
        }
        return nil
    }()

    // MARK: - Neural nodes (mapped to lobe positions in the image)
    //  Positions are in "brain units" relative to the centre of the drawn character.
    //  x positive = right, y positive = up.
    struct Node {
        let x, y, r: CGFloat
        let color: NSColor
        let phase, llmWeight: CGFloat
    }
    private let nodes: [Node] = [
        // 0 — LLM core          (pink left lobe)
        Node(x:-52, y: 50, r:26, color:NSColor(red:1.0, green:0.52,blue:0.70,alpha:1), phase:0.0, llmWeight:1.0),
        // 1 — Knowledge Base    (yellow top-right)
        Node(x: 28, y: 72, r:24, color:NSColor(red:1.0, green:0.82,blue:0.18,alpha:1), phase:0.9, llmWeight:0.7),
        // 2 — Prompt Processor  (pink front-left)
        Node(x:-18, y: 66, r:22, color:NSColor(red:1.0, green:0.62,blue:0.76,alpha:1), phase:1.8, llmWeight:0.8),
        // 3 — Reasoning Engine  (blue right)
        Node(x: 58, y: 48, r:22, color:NSColor(red:0.50,green:0.72,blue:1.0, alpha:1), phase:2.7, llmWeight:0.6),
        // 4 — Tool Use / API    (green front-bottom)
        Node(x:-22, y:-12, r:18, color:NSColor(red:0.38,green:0.82,blue:0.42,alpha:1), phase:3.6, llmWeight:0.5),
        // 5 — Output Generator  (green/purple lower)
        Node(x: 20, y:-14, r:18, color:NSColor(red:0.70,green:0.45,blue:0.95,alpha:1), phase:4.5, llmWeight:0.5),
        // 6 — Evaluation/Feedback (purple back-right)
        Node(x: 66, y: 10, r:20, color:NSColor(red:0.55,green:0.72,blue:1.0, alpha:1), phase:5.4, llmWeight:0.4),
        // 7 — extra inner spark (centre-left)
        Node(x:-66, y:  2, r:16, color:NSColor(red:0.65,green:0.38,blue:0.92,alpha:1), phase:6.3, llmWeight:0.9),
    ]
    private let edges: [(Int,Int)] = [
        (0,2),(2,1),(1,3),(0,7),(3,6),(7,4),(6,5),(4,5),(2,7),(1,6)
    ]

    // MARK: - Labels
    // Each label matches one node / lobe and a step in the LLM pipeline.
    // angle: radians from +x axis (0=right, π/2=up).
    // dist:  label centre distance from brain centre in "brain units".
    struct BrainLabel {
        let text: String
        let nodeIdx: Int
        let angle: CGFloat        // where to place the label
        let dist: CGFloat         // radius from brain centre
        let pipelineOrder: Int    // 0-6, order in LLM processing chain
    }
    private let labels: [BrainLabel] = [
        BrainLabel(text:"Prompt\nInput",   nodeIdx:2, angle: CGFloat.pi * 0.72, dist:165, pipelineOrder:0),
        BrainLabel(text:"LLM\nCore",       nodeIdx:0, angle: CGFloat.pi * 0.95, dist:165, pipelineOrder:1),
        BrainLabel(text:"Knowledge\nBase", nodeIdx:1, angle: CGFloat.pi * 0.18, dist:165, pipelineOrder:2),
        BrainLabel(text:"Reasoning\nEngine",nodeIdx:3,angle: CGFloat.pi * -0.10,dist:165, pipelineOrder:3),
        BrainLabel(text:"Tool Use\n& API", nodeIdx:4, angle: CGFloat.pi * -0.55,dist:165, pipelineOrder:4),
        BrainLabel(text:"Output\nGenerator",nodeIdx:5,angle: CGFloat.pi * -0.78,dist:165, pipelineOrder:5),
        BrainLabel(text:"Evaluation\n& Feedback",nodeIdx:6,angle:CGFloat.pi * -0.30,dist:165, pipelineOrder:6),
    ]

    override var isFlipped: Bool { false }

    // MARK: - Tick

    func advance(by dt: CGFloat) {
        t += dt
        let activity = (gpuLoad + cpuLoad) / 2

        // Sleep transition
        let targetSleep: CGFloat = activity < 0.05 ? 1 : 0
        sleepLevel += (targetSleep - sleepLevel) * dt * (targetSleep > sleepLevel ? 0.3 : 0.8)

        // Pipeline flow — advances faster when LLM is active
        if llmOnGPU || llmOnCPU {
            pipelinePhase = fmod(pipelinePhase + dt * (0.4 + gpuLoad * 0.8), 1.0)
        } else {
            pipelinePhase = fmod(pipelinePhase + dt * 0.12, 1.0)
        }

        // ZZZ spawning
        if sleepLevel > 0.4 {
            nextZSpawn -= dt
            if nextZSpawn <= 0 {
                nextZSpawn = 1.2 - sleepLevel * 0.6
                let idx = zzzList.count % 3
                zzzList.append(ZZZ(x: CGFloat.random(in:8...30), y: CGFloat.random(in:-5...10),
                                   life:0, maxLife:2.4, size:14+CGFloat(idx)*6, index:idx))
            }
        }
        zzzList = zzzList.compactMap { var z = $0
            z.life += dt; z.y += dt*20; z.x += dt*7
            return z.life < z.maxLife ? z : nil
        }
        needsDisplay = true
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        let unit = min(w, h) / 340.0

        // Bob/sway/tilt — amplitude & speed scale with GPU load (looks like running)
        let speed  = 1.0 + gpuLoad * 5.5
        let bobAmp = unit * (1.5 + gpuLoad * 10.0)
        let bobY   = sin(t * speed * 2.0) * bobAmp
        let swayX  = sin(t * speed * 0.9 + 1.2) * unit * gpuLoad * 5.0
        let tilt   = sin(t * speed * 2.0 + 0.3) * gpuLoad * 0.04
        let breath = 1.0 + sin(t * 1.1) * (0.005 + gpuLoad * 0.008)
        let scale  = breath * unit

        ctx.saveGState()
        ctx.translateBy(x: w/2 + swayX, y: h/2 + bobY)
        ctx.scaleBy(x: scale, y: scale)
        ctx.rotate(by: tilt)

        drawBrainImage(ctx)
        drawEdges(ctx)
        drawNodes(ctx)
        drawLabels(ctx, unit: unit)
        drawSleepOverlay(ctx)
        drawZZZ(ctx)

        ctx.restoreGState()
    }

    // MARK: - Brain image

    private func drawBrainImage(_ ctx: CGContext) {
        guard let img = brainImage else { drawFallbackBrain(ctx); return }
        let size: CGFloat = 310
        let rect = CGRect(x: -size/2, y: -size/2 - 18, width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        img.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFallbackBrain(_ ctx: CGContext) {
        ctx.addEllipse(in: CGRect(x:-90, y:-60, width:180, height:155))
        ctx.setFillColor(NSColor(red:1,green:0.75,blue:0.82,alpha:1).cgColor)
        ctx.fillPath()
    }

    // MARK: - Node activation

    private func nodeActivation(_ n: Node) -> CGFloat {
        let spd  = 0.8 + gpuLoad * 2.5
        let base = (sin(t * spd * .pi + n.phase) + 1) / 2
        let llm  = (llmOnGPU || llmOnCPU) ? n.llmWeight * 0.45 : 0
        let cpu  = cpuLoad  * (n.phase > 2.5 && n.phase < 4 ? 0.28 : 0.05)
        let gpu  = gpuLoad  * (n.phase < 2.5 ? 0.32 : 0.08)
        return min(1, base * (0.28 + gpuLoad * 0.45) + llm + cpu + gpu)
    }

    // Pipeline activation boost for a given label (0-1 pulse as pipeline flows through)
    private func pipelineActivation(order: Int) -> CGFloat {
        let totalSteps = CGFloat(labels.count)
        let myPhase = CGFloat(order) / totalSteps
        let delta = fmod(abs(pipelinePhase - myPhase), 1.0)
        let d = min(delta, 1.0 - delta)
        let pulse = max(0, 1 - d * totalSteps * 1.4)
        return pulse * (llmOnGPU || llmOnCPU ? 1.0 : 0.35)
    }

    // MARK: - Nodes & Edges

    private func drawEdges(_ ctx: CGContext) {
        for (i, j) in edges {
            let a = nodeActivation(nodes[i])
            let b = nodeActivation(nodes[j])
            let v = (a + b) / 2
            guard v > 0.25 else { continue }
            ctx.setStrokeColor(NSColor.white.withAlphaComponent((v-0.25)/0.75 * 0.55).cgColor)
            ctx.setLineWidth(0.5 + v * 1.2)
            ctx.move(to:    CGPoint(x:nodes[i].x, y:nodes[i].y + 38))
            ctx.addLine(to: CGPoint(x:nodes[j].x, y:nodes[j].y + 38))
            ctx.strokePath()
        }
    }

    private func drawNodes(_ ctx: CGContext) {
        for n in nodes {
            let act = nodeActivation(n)
            guard act > 0.05 else { continue }
            let ny = n.y + 38
            // Outer glow
            let gr = n.r * (1 + act * 0.9)
            ctx.addEllipse(in: CGRect(x:n.x-gr, y:ny-gr, width:gr*2, height:gr*2))
            ctx.setFillColor(n.color.withAlphaComponent(act * 0.26).cgColor); ctx.fillPath()
            // Core dot
            let cr = n.r * 0.30 * (0.6 + act * 0.7)
            ctx.addEllipse(in: CGRect(x:n.x-cr, y:ny-cr, width:cr*2, height:cr*2))
            ctx.setFillColor(n.color.withAlphaComponent(0.40 + act * 0.60).cgColor); ctx.fillPath()
        }
    }

    // MARK: - Labels

    private func drawLabels(_ ctx: CGContext, unit: CGFloat) {
        // Labels are drawn in "brain-unit" space (already inside the scaled ctx).
        // We inverse-scale font sizes so they stay readable regardless of view size.
        let invScale = 1.0 / (unit > 0 ? unit : 1)

        for lbl in labels {
            let node = nodes[lbl.nodeIdx]
            let act  = nodeActivation(node)
            let pipe = pipelineActivation(order: lbl.pipelineOrder)

            // Combined activation for this label
            let combined = min(1.0, act * 0.6 + pipe * 0.7 + gpuLoad * 0.2)

            // Label grows with GPU load — base 8.5pt, up to 14pt at max load
            let baseFontSize: CGFloat = 8.5
            let fontSize = (baseFontSize + gpuLoad * 5.5 + pipe * 3.0) * invScale

            // Colour: node colour, alpha scales with activity
            let baseAlpha = 0.38 + combined * 0.62
            let textColor = node.color.withAlphaComponent(baseAlpha)
            let dotColor  = node.color.withAlphaComponent(0.3 + combined * 0.7)

            // Label centre position
            let lx = cos(lbl.angle) * lbl.dist
            let ly = sin(lbl.angle) * lbl.dist

            // Connecting line from lobe to label
            let nodePt  = CGPoint(x: node.x,       y: node.y + 38)
            let labelPt = CGPoint(x: lx,            y: ly)
            let lineAlpha = 0.18 + combined * 0.42

            // Dashed connecting line
            ctx.saveGState()
            ctx.setLineDash(phase: t * 12 * invScale, lengths: [3 * invScale, 3 * invScale])
            ctx.setStrokeColor(node.color.withAlphaComponent(lineAlpha).cgColor)
            ctx.setLineWidth(0.8 * invScale)
            ctx.move(to: nodePt); ctx.addLine(to: labelPt)
            ctx.strokePath()
            ctx.restoreGState()

            // Small dot at lobe end of line
            let dotR: CGFloat = (1.8 + combined * 2.0) * invScale
            ctx.addEllipse(in: CGRect(x:nodePt.x-dotR, y:nodePt.y-dotR,
                                      width:dotR*2, height:dotR*2))
            ctx.setFillColor(dotColor.cgColor); ctx.fillPath()

            // Background pill behind text (semi-transparent, scales with activation)
            let pillAlpha = 0.08 + combined * 0.20
            let pillColor = node.color.withAlphaComponent(pillAlpha)

            // Draw label text (NSString in CGContext coord space)
            let font = NSFont.systemFont(ofSize: fontSize, weight: combined > 0.5 ? .semibold : .medium)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]
            let attrStr = NSAttributedString(string: lbl.text, attributes: attrs)
            let textSize = attrStr.size()

            // Pill rect
            let pillPad: CGFloat = 3.5 * invScale
            let pillRect = CGRect(
                x: lx - textSize.width/2 - pillPad,
                y: ly - textSize.height/2 - pillPad,
                width: textSize.width + pillPad*2,
                height: textSize.height + pillPad*2
            )
            let pillPath = CGPath(roundedRect: pillRect,
                                  cornerWidth: 4*invScale, cornerHeight: 4*invScale,
                                  transform: nil)
            ctx.addPath(pillPath)
            ctx.setFillColor(pillColor.cgColor); ctx.fillPath()

            // Pill border
            ctx.addPath(pillPath)
            ctx.setStrokeColor(node.color.withAlphaComponent(0.12 + combined*0.35).cgColor)
            ctx.setLineWidth(0.6 * invScale)
            ctx.strokePath()

            // Text
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            attrStr.draw(at: CGPoint(x: lx - textSize.width/2,
                                     y: ly - textSize.height/2))
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    // MARK: - Sleep overlay

    private func drawSleepOverlay(_ ctx: CGContext) {
        guard sleepLevel > 0.1 else { return }
        for ex: CGFloat in [-30, 32] {
            let ey: CGFloat = 30
            let lidH = 20.0 * (0.3 + sleepLevel * 0.65)
            ctx.addEllipse(in: CGRect(x:ex-20, y:ey-2, width:40, height:lidH*2))
            ctx.setFillColor(NSColor(red:1,green:0.75,blue:0.82,alpha:sleepLevel*0.93).cgColor)
            ctx.fillPath()
        }
    }

    // MARK: - ZZZ

    private func drawZZZ(_ ctx: CGContext) {
        guard !zzzList.isEmpty else { return }
        let letters = ["z","z","Z"]
        for z in zzzList {
            let p = z.life / z.maxLife
            let a = p < 0.15 ? p/0.15 : p > 0.75 ? (1-p)/0.25 : 1.0
            ctx.saveGState()
            ctx.translateBy(x: z.x+55, y: z.y+130)
            ctx.scaleBy(x: 0.7+p*0.5, y: 0.7+p*0.5)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: z.size, weight: .bold),
                .foregroundColor: NSColor(red:0.7,green:0.85,blue:1,alpha:a*sleepLevel)
            ]
            (letters[z.index] as NSString).draw(at: .zero, withAttributes: attrs)
            ctx.restoreGState()
        }
    }
}
