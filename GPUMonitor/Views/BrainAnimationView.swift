import AppKit

/// Animated kawaii brain character. Call `advance(by:)` each frame.
final class BrainAnimationView: NSView {
    var gpuLoad: CGFloat = 0   // 0–1
    var cpuLoad: CGFloat = 0   // 0–1

    private var t: CGFloat = 0
    private var eyeBlinkT: CGFloat = 0
    private var blinking = false
    private var particleT: CGFloat = 0

    // Simple particles for high-load sparks
    private struct Particle {
        var x, y, vx, vy, life, maxLife: CGFloat
        var color: NSColor
    }
    private var particles: [Particle] = []

    override var isFlipped: Bool { false }

    /// Advance the animation clock by `dt` seconds.
    func advance(by dt: CGFloat) {
        t += dt

        // Blink every ~4s
        eyeBlinkT += dt
        if eyeBlinkT > 4.0 {
            blinking = true
            if eyeBlinkT > 4.12 { blinking = false; eyeBlinkT = 0 }
        }

        // Spawn particles at high GPU load
        particleT += dt
        let spawnRate: CGFloat = gpuLoad > 0.6 ? 0.04 : 0.12
        if particleT > spawnRate && gpuLoad > 0.3 {
            particleT = 0
            let colors: [NSColor] = [
                NSColor(red: 0, green: 0.9, blue: 0.5, alpha: 1),
                NSColor(red: 0.4, green: 0.6, blue: 1, alpha: 1),
                NSColor(red: 1, green: 0.8, blue: 0, alpha: 1),
                NSColor(red: 1, green: 0.3, blue: 0.8, alpha: 1),
            ]
            let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
            let speed: CGFloat = 30 + CGFloat.random(in: 0...40) * gpuLoad
            particles.append(Particle(
                x: CGFloat.random(in: -30...30),
                y: CGFloat.random(in: 20...60),
                vx: cos(angle) * speed,
                vy: sin(angle) * speed + 20,
                life: 0, maxLife: 0.8 + CGFloat.random(in: 0...0.4),
                color: colors.randomElement()!
            ))
        }

        // Update particles
        particles = particles.compactMap { var p = $0
            p.life += dt
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.vy -= 60 * dt   // gravity
            return p.life < p.maxLife ? p : nil
        }

        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let w = bounds.width, h = bounds.height
        let unit = min(w, h) / 320.0

        // Breathing scale
        let breathAmp: CGFloat = 0.015 + gpuLoad * 0.025
        let breathScale = 1.0 + sin(t * 1.3) * breathAmp

        // Bounce Y – amplitude and speed scale with GPU%
        let bounceAmp  = unit * (4 + gpuLoad * 28)
        let bounceSpeed = 1.0 + gpuLoad * 3.5
        let bounceY = sin(t * bounceSpeed * .pi) * bounceAmp

        // Lateral wobble at high load
        let wobbleX = gpuLoad > 0.5 ? sin(t * 7.3) * unit * gpuLoad * 8 : 0

        ctx.saveGState()
        ctx.translateBy(x: w / 2 + wobbleX, y: h / 2 + bounceY)
        ctx.scaleBy(x: breathScale * unit, y: breathScale * unit)

        drawGlow(ctx: ctx)
        drawBrainBody(ctx: ctx)
        drawFace(ctx: ctx)
        drawParticles(ctx: ctx, unit: unit, bounceY: bounceY)

        ctx.restoreGState()
    }

    // MARK: - Drawing helpers

    private func drawGlow(ctx: CGContext) {
        let intensity = 0.15 + gpuLoad * 0.55
        let radius: CGFloat = 90 + gpuLoad * 50
        let colors = [
            CGColor(red: 1, green: 0.5, blue: 0.8, alpha: intensity),
            CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        ]
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: [0, 1]
        ) else { return }
        ctx.drawRadialGradient(gradient,
            startCenter: .zero, startRadius: 0,
            endCenter: .zero, endRadius: radius,
            options: [])
    }

    private func drawBrainBody(ctx: CGContext) {
        // ── Color sections (matching kawaii reference) ─────────────────
        // Back-left purple lobe
        drawLobe(ctx: ctx, cx: -55, cy: -20, rx: 55, ry: 50,
                 color: NSColor(red: 0.65, green: 0.4, blue: 0.9, alpha: 1))
        // Bottom-center green lobe
        drawLobe(ctx: ctx, cx: 0, cy: -38, rx: 65, ry: 42,
                 color: NSColor(red: 0.4, green: 0.8, blue: 0.3, alpha: 1))
        // Right blue lobe
        drawLobe(ctx: ctx, cx: 58, cy: -5, rx: 50, ry: 55,
                 color: NSColor(red: 0.55, green: 0.75, blue: 1, alpha: 1))
        // Upper-right yellow lobe
        drawLobe(ctx: ctx, cx: 38, cy: 48, rx: 55, ry: 52,
                 color: NSColor(red: 1, green: 0.85, blue: 0.25, alpha: 1))
        // Main pink body (front / dominant)
        drawMainBody(ctx: ctx)
        // Top bumps
        drawTopBumps(ctx: ctx)
        // Center divider crease
        drawCrease(ctx: ctx)
    }

    private func drawLobe(ctx: CGContext, cx: CGFloat, cy: CGFloat,
                          rx: CGFloat, ry: CGFloat, color: NSColor) {
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx*2, height: ry*2))
        ctx.addPath(path)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawMainBody(ctx: CGContext) {
        // Big pink blob – the face area
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -80, y: -65, width: 160, height: 145))
        ctx.addPath(path)
        ctx.setFillColor(NSColor(red: 1, green: 0.75, blue: 0.82, alpha: 1).cgColor)
        ctx.fillPath()

        // Subtle highlight top
        let hPath = CGMutablePath()
        hPath.addEllipse(in: CGRect(x: -50, y: 20, width: 100, height: 50))
        ctx.addPath(hPath)
        ctx.setFillColor(NSColor(white: 1, alpha: 0.25).cgColor)
        ctx.fillPath()
    }

    private func drawTopBumps(ctx: CGContext) {
        let bumpColor = NSColor(red: 1, green: 0.72, blue: 0.80, alpha: 1).cgColor
        let bumps: [(CGFloat, CGFloat, CGFloat)] = [
            (-72, 55, 32), (-35, 72, 36), (0, 78, 36), (36, 70, 34), (68, 50, 30)
        ]
        for (bx, by, br) in bumps {
            ctx.addEllipse(in: CGRect(x: bx-br, y: by-br, width: br*2, height: br*2))
            ctx.setFillColor(bumpColor)
            ctx.fillPath()
        }
        // Bump highlights
        for (bx, by, br) in bumps {
            ctx.addEllipse(in: CGRect(x: bx-br*0.4, y: by+br*0.1, width: br*0.7, height: br*0.4))
            ctx.setFillColor(NSColor(white: 1, alpha: 0.30).cgColor)
            ctx.fillPath()
        }
    }

    private func drawCrease(ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(red: 0.9, green: 0.55, blue: 0.65, alpha: 0.6).cgColor)
        ctx.setLineWidth(3)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 75))
        path.addCurve(to: CGPoint(x: 0, y: -30),
                      control1: CGPoint(x: 12, y: 40),
                      control2: CGPoint(x: -10, y: 10))
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawFace(ctx: CGContext) {
        // ── Eyes ──────────────────────────────────────────────────────
        let eyeY: CGFloat = 10
        for ex in [-28.0, 28.0] as [CGFloat] {
            // Eye white
            ctx.addEllipse(in: CGRect(x: ex-16, y: eyeY-18, width: 32, height: blinking ? 5 : 32))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()

            if !blinking {
                // Iris – purple (matches reference)
                ctx.addEllipse(in: CGRect(x: ex-11, y: eyeY-13, width: 22, height: 22))
                ctx.setFillColor(NSColor(red: 0.45, green: 0.25, blue: 0.75, alpha: 1).cgColor)
                ctx.fillPath()

                // Pupil
                ctx.addEllipse(in: CGRect(x: ex-6, y: eyeY-8, width: 12, height: 12))
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fillPath()

                // Shine
                ctx.addEllipse(in: CGRect(x: ex-8, y: eyeY+0, width: 7, height: 7))
                ctx.addEllipse(in: CGRect(x: ex+2, y: eyeY+4, width: 4, height: 4))
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fillPath()
            }
        }

        // ── Eyebrows ──────────────────────────────────────────────────
        let browY: CGFloat = 30
        ctx.setStrokeColor(NSColor(red: 0.35, green: 0.18, blue: 0.18, alpha: 0.9).cgColor)
        ctx.setLineWidth(4)
        ctx.setLineCap(.round)
        for ex in [-28.0, 28.0] as [CGFloat] {
            let tilt: CGFloat = gpuLoad > 0.6 ? (ex < 0 ? 6 : -6) : 0  // angry at high load
            let p = CGMutablePath()
            p.move(to: CGPoint(x: ex - 10, y: browY + tilt))
            p.addCurve(to: CGPoint(x: ex + 10, y: browY - tilt),
                       control1: CGPoint(x: ex - 5, y: browY + 4 + tilt),
                       control2: CGPoint(x: ex + 5, y: browY - 4 - tilt))
            ctx.addPath(p); ctx.strokePath()
        }

        // ── Blush cheeks ──────────────────────────────────────────────
        for cx in [-45.0, 45.0] as [CGFloat] {
            ctx.addEllipse(in: CGRect(x: cx-14, y: -8, width: 28, height: 16))
            ctx.setFillColor(NSColor(red: 1, green: 0.5, blue: 0.6, alpha: 0.45).cgColor)
            ctx.fillPath()
        }

        // ── Mouth ─────────────────────────────────────────────────────
        // Happy / open smile intensity at high load
        let smileOpen = gpuLoad > 0.5
        ctx.setFillColor(NSColor(red: 0.35, green: 0.18, blue: 0.18, alpha: 0.9).cgColor)
        ctx.setStrokeColor(NSColor(red: 0.35, green: 0.18, blue: 0.18, alpha: 0.9).cgColor)
        ctx.setLineWidth(3.5)
        ctx.setLineCap(.round)
        let mp = CGMutablePath()
        mp.move(to: CGPoint(x: -16, y: -20))
        mp.addQuadCurve(to: CGPoint(x: 16, y: -20),
                        control: CGPoint(x: 0, y: smileOpen ? -36 : -30))
        ctx.addPath(mp); ctx.strokePath()

        // Teeth when smiling wide
        if smileOpen {
            ctx.addEllipse(in: CGRect(x: -10, y: -30, width: 20, height: 12))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
        }

        // ── Raised finger at very high load ───────────────────────────
        if gpuLoad > 0.7 {
            drawFinger(ctx: ctx)
        }
    }

    private func drawFinger(ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: -68, y: 5)
        // Arm
        ctx.setFillColor(NSColor(red: 1, green: 0.75, blue: 0.82, alpha: 1).cgColor)
        let arm = CGMutablePath()
        arm.addRoundedRect(in: CGRect(x: -8, y: 0, width: 16, height: 35), cornerWidth: 8, cornerHeight: 8)
        ctx.addPath(arm); ctx.fillPath()
        // Finger
        let finger = CGMutablePath()
        finger.addRoundedRect(in: CGRect(x: -5, y: 28, width: 10, height: 22), cornerWidth: 5, cornerHeight: 5)
        ctx.addPath(finger); ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawParticles(ctx: CGContext, unit: CGFloat, bounceY: CGFloat) {
        for p in particles {
            let alpha = (1 - p.life / p.maxLife) * 0.9
            let r = max(1, (1 - p.life / p.maxLife) * 5)
            let col = p.color.withAlphaComponent(alpha)
            ctx.addEllipse(in: CGRect(x: p.x / unit - r, y: p.y / unit - r,
                                       width: r*2, height: r*2))
            ctx.setFillColor(col.cgColor)
            ctx.fillPath()
        }
    }
}
