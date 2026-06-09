import AppKit

/// Kawaii brain with neural-mapping blink animation.
/// Lobes light up proportional to GPU/CPU load; LLM-active regions glow brighter.
final class BrainAnimationView: NSView {

    var gpuLoad:  CGFloat = 0   // 0–1
    var cpuLoad:  CGFloat = 0   // 0–1
    var llmOnGPU: Bool = false  // ollama running on GPU?
    var llmOnCPU: Bool = false  // ollama running on CPU?

    private var t: CGFloat = 0
    private var eyeBlinkT: CGFloat = 0
    private var blinking = false

    // ── Brain nodes (normalised: 0,0 = brain centre, units ≈ pixels @ 300px brain) ──
    struct Node {
        let x, y: CGFloat
        let r: CGFloat          // base radius
        let color: NSColor
        let phase: CGFloat      // blink phase offset
        var llmWeight: CGFloat  // how much LLM activity boosts this node
    }

    private let nodes: [Node] = [
        // top-left bump  (language / LLM primary)
        Node(x: -50, y: 70, r: 28, color: NSColor(red:1,   green:0.55, blue:0.72, alpha:1), phase: 0.0,  llmWeight: 1.0),
        // top-center-left
        Node(x: -16, y: 82, r: 30, color: NSColor(red:1,   green:0.58, blue:0.75, alpha:1), phase: 0.7,  llmWeight: 0.8),
        // top-center-right  (knowledge/memory)
        Node(x:  20, y: 80, r: 30, color: NSColor(red:1,   green:0.88, blue:0.20, alpha:1), phase: 1.4,  llmWeight: 0.7),
        // top-right bump  (reasoning)
        Node(x:  56, y: 62, r: 26, color: NSColor(red:0.55, green:0.75, blue:1,   alpha:1), phase: 2.1,  llmWeight: 0.5),
        // left temporal  (memory/context)
        Node(x: -72, y:  8, r: 24, color: NSColor(red:0.65, green:0.40, blue:0.90, alpha:1), phase: 2.8, llmWeight: 0.9),
        // right parietal (processing)
        Node(x:  70, y: 12, r: 24, color: NSColor(red:0.55, green:0.75, blue:1,   alpha:1), phase: 3.5,  llmWeight: 0.4),
        // center-left (motor / face)
        Node(x: -26, y: -8, r: 22, color: NSColor(red:1,   green:0.72, blue:0.82, alpha:1), phase: 4.2,  llmWeight: 0.6),
        // center-right (output)
        Node(x:  28, y: -6, r: 22, color: NSColor(red:0.40, green:0.82, blue:0.45, alpha:1), phase: 4.9, llmWeight: 0.5),
    ]

    // Pairs of node indices that are connected
    private let edges: [(Int,Int)] = [
        (0,1),(1,2),(2,3),    // top arc
        (0,4),(3,5),          // side drops
        (4,6),(5,7),          // lower
        (6,7),                // bottom bridge
        (1,4),(2,5),          // diagonals
        (0,6),(3,7),          // front cross
    ]

    override var isFlipped: Bool { false }

    // MARK: - Animation tick

    func advance(by dt: CGFloat) {
        t += dt
        eyeBlinkT += dt
        if eyeBlinkT > 3.8 {
            blinking = true
            if eyeBlinkT > 3.95 { blinking = false; eyeBlinkT = 0 }
        }
        needsDisplay = true
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height
        let unit = min(w, h) / 300.0

        // Subtle bob — gentle at idle, more pronounced when working hard
        let bobAmp  = unit * (2 + gpuLoad * 10)          // 2px idle → 12px at full load
        let bobY    = sin(t * 1.4) * bobAmp
        // Very slight sway left-right at high load
        let swayAmp = unit * gpuLoad * 4
        let swayX   = sin(t * 0.9 + 1.2) * swayAmp
        // Tiny breathing scale
        let breathScale = 1.0 + sin(t * 1.1) * (0.008 + gpuLoad * 0.012)

        ctx.saveGState()
        ctx.translateBy(x: w / 2 + swayX, y: h / 2 + bobY)
        ctx.scaleBy(x: breathScale * unit, y: breathScale * unit)

        drawBrainBody(ctx)
        drawEdges(ctx)
        drawNodes(ctx)
        drawFace(ctx)

        ctx.restoreGState()
    }

    // MARK: - Activation helper

    private func activation(for node: Node) -> CGFloat {
        // Base neural blink: sine wave at node-specific frequency
        let baseSpeed = 0.8 + gpuLoad * 2.5
        let base = (sin(t * baseSpeed * .pi + node.phase) + 1) / 2  // 0–1

        // LLM boost for language-heavy nodes
        let llmBoost: CGFloat = (llmOnGPU || llmOnCPU) ? node.llmWeight * 0.5 : 0

        // CPU load lifts memory nodes (4,5), GPU load lifts top nodes (0,1,2,3)
        let cpuBoost = cpuLoad * (node.phase > 2.5 && node.phase < 4 ? 0.3 : 0.05)
        let gpuBoost = gpuLoad * (node.phase < 2.5 ? 0.35 : 0.08)

        return min(1, base * (0.4 + gpuLoad * 0.4) + llmBoost + cpuBoost + gpuBoost)
    }

    // MARK: - Brain body

    private func drawBrainBody(_ ctx: CGContext) {
        // Back colour sections
        drawLobe(ctx, cx: -54, cy: -18, rx: 54, ry: 50,
                 color: NSColor(red:0.65, green:0.40, blue:0.90, alpha:0.85))
        drawLobe(ctx, cx:   0, cy: -36, rx: 64, ry: 42,
                 color: NSColor(red:0.40, green:0.82, blue:0.35, alpha:0.85))
        drawLobe(ctx, cx:  58, cy:  -4, rx: 50, ry: 54,
                 color: NSColor(red:0.55, green:0.75, blue:1.00, alpha:0.85))
        drawLobe(ctx, cx:  38, cy:  48, rx: 54, ry: 50,
                 color: NSColor(red:1.00, green:0.88, blue:0.25, alpha:0.85))
        // Main pink body
        ctx.addEllipse(in: CGRect(x: -80, y: -64, width: 160, height: 145))
        ctx.setFillColor(NSColor(red:1, green:0.75, blue:0.82, alpha:1).cgColor)
        ctx.fillPath()
        // Top bumps
        for (bx, by, br): (CGFloat,CGFloat,CGFloat) in [(-70,55,31),(-34,72,35),(2,78,35),(38,70,33),(68,50,29)] {
            ctx.addEllipse(in: CGRect(x:bx-br, y:by-br, width:br*2, height:br*2))
            ctx.setFillColor(NSColor(red:1, green:0.72, blue:0.80, alpha:1).cgColor)
            ctx.fillPath()
        }
        // Centre crease
        ctx.setStrokeColor(NSColor(red:0.88, green:0.54, blue:0.64, alpha:0.55).cgColor)
        ctx.setLineWidth(2.5)
        let crease = CGMutablePath()
        crease.move(to: CGPoint(x:0, y:75))
        crease.addCurve(to: CGPoint(x:0, y:-30),
                        control1: CGPoint(x:11, y:38), control2: CGPoint(x:-9, y:8))
        ctx.addPath(crease); ctx.strokePath()
    }

    private func drawLobe(_ ctx: CGContext, cx: CGFloat, cy: CGFloat,
                          rx: CGFloat, ry: CGFloat, color: NSColor) {
        ctx.addEllipse(in: CGRect(x:cx-rx, y:cy-ry, width:rx*2, height:ry*2))
        ctx.setFillColor(color.cgColor); ctx.fillPath()
    }

    // MARK: - Neural edges

    private func drawEdges(_ ctx: CGContext) {
        for (i, j) in edges {
            let a = activation(for: nodes[i])
            let b = activation(for: nodes[j])
            let combined = (a + b) / 2
            guard combined > 0.25 else { continue }

            let alpha = (combined - 0.25) / 0.75 * 0.7
            let ni = nodes[i], nj = nodes[j]
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(0.8 + combined * 1.5)
            ctx.move(to: CGPoint(x: ni.x, y: ni.y))
            ctx.addLine(to: CGPoint(x: nj.x, y: nj.y))
            ctx.strokePath()
        }
    }

    // MARK: - Neural nodes

    private func drawNodes(_ ctx: CGContext) {
        for node in nodes {
            let act = activation(for: node)
            guard act > 0.05 else { continue }

            // Outer glow ring
            let glowR = node.r * (1.0 + act * 0.8)
            ctx.addEllipse(in: CGRect(x:node.x-glowR, y:node.y-glowR,
                                      width:glowR*2, height:glowR*2))
            ctx.setFillColor(node.color.withAlphaComponent(act * 0.35).cgColor)
            ctx.fillPath()

            // Core dot
            let coreR = node.r * 0.38 * (0.6 + act * 0.7)
            ctx.addEllipse(in: CGRect(x:node.x-coreR, y:node.y-coreR,
                                      width:coreR*2, height:coreR*2))
            ctx.setFillColor(node.color.withAlphaComponent(0.5 + act * 0.5).cgColor)
            ctx.fillPath()

            // Bright centre highlight
            let sparkR = coreR * 0.45
            ctx.addEllipse(in: CGRect(x:node.x-sparkR, y:node.y+coreR*0.2-sparkR,
                                      width:sparkR*2, height:sparkR*2))
            ctx.setFillColor(NSColor.white.withAlphaComponent(act * 0.6).cgColor)
            ctx.fillPath()
        }
    }

    // MARK: - Face

    private func drawFace(_ ctx: CGContext) {
        let eyeY: CGFloat = 10
        for ex: CGFloat in [-28, 28] {
            // White
            ctx.addEllipse(in: CGRect(x:ex-15, y:eyeY-17, width:30, height: blinking ? 4 : 30))
            ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
            if !blinking {
                // Iris
                ctx.addEllipse(in: CGRect(x:ex-10, y:eyeY-12, width:20, height:20))
                ctx.setFillColor(NSColor(red:0.45, green:0.25, blue:0.75, alpha:1).cgColor)
                ctx.fillPath()
                // Pupil
                ctx.addEllipse(in: CGRect(x:ex-6, y:eyeY-8, width:12, height:12))
                ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
                // Shine
                ctx.addEllipse(in: CGRect(x:ex-7, y:eyeY+0, width:6, height:6))
                ctx.addEllipse(in: CGRect(x:ex+1, y:eyeY+3, width:3.5, height:3.5))
                ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
            }
        }
        // Blush
        for cx: CGFloat in [-44, 44] {
            ctx.addEllipse(in: CGRect(x:cx-13, y:-7, width:26, height:15))
            ctx.setFillColor(NSColor(red:1, green:0.50, blue:0.60, alpha:0.40).cgColor)
            ctx.fillPath()
        }
        // Smile — gets wider with activity
        let activity = (gpuLoad + cpuLoad) / 2
        ctx.setStrokeColor(NSColor(red:0.35, green:0.18, blue:0.18, alpha:0.85).cgColor)
        ctx.setLineWidth(3); ctx.setLineCap(.round)
        let sm = CGMutablePath()
        sm.move(to: CGPoint(x:-15, y:-20))
        sm.addQuadCurve(to: CGPoint(x:15, y:-20),
                        control: CGPoint(x:0, y: -28 - activity * 8))
        ctx.addPath(sm); ctx.strokePath()
    }
}
