import AppKit

/// Displays the kawaii brain character image.
/// When GPU % is high:
///   • Wobbles side-to-side (thinking hard)
///   • Blinks — frequency and speed scale with GPU load
final class BrainAnimationView: NSView {

    // MARK: - Inputs
    var gpuLoad:  CGFloat = 0   // 0-1
    var cpuLoad:  CGFloat = 0
    var llmOnGPU: Bool = false
    var llmOnCPU: Bool = false

    // MARK: - State
    private var t: CGFloat = 0

    // Blink state
    private var blinkPhase: CGFloat = 0   // 0 = eyes open, 1 = eyes fully closed
    private var nextBlink:  CGFloat = 2.0 // seconds until next blink
    private var isBlinking: Bool    = false

    // Brain image loaded once from bundle
    private lazy var brainImage: NSImage? = {
        Bundle(for: BrainAnimationView.self)
            .url(forResource: "BrainCharacter", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
    }()

    override var isFlipped: Bool { false }

    // MARK: - Tick

    func advance(by dt: CGFloat) {
        t += dt

        // Blink timer — fires more often at high GPU load
        let blinkInterval: CGFloat = max(0.6, 3.5 - gpuLoad * 2.8)
        nextBlink -= dt
        if nextBlink <= 0 {
            nextBlink = blinkInterval + CGFloat.random(in: 0...0.8)
            isBlinking = true
        }

        // Animate blink: close then open (total ~0.25s)
        if isBlinking {
            blinkPhase += dt / 0.12
            if blinkPhase >= 1.0 {
                blinkPhase = max(0, blinkPhase - dt / 0.10)
                if blinkPhase <= 0 { isBlinking = false; blinkPhase = 0 }
            }
        }

        needsDisplay = true
    }

    // MARK: - Draw

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let w = bounds.width, h = bounds.height

        // ── Wobble when GPU is busy ────────────────────────────────────
        // Amplitude and speed both scale with GPU load
        let wobbleAmp:   CGFloat = gpuLoad * 6.0          // max ±6pt side-to-side
        let wobbleSpeed: CGFloat = 1.5 + gpuLoad * 5.0    // faster when busy
        let shakeX = sin(t * wobbleSpeed * .pi * 2) * wobbleAmp
        let shakeY = sin(t * wobbleSpeed * .pi * 1.3 + 0.8) * wobbleAmp * 0.4

        // Tiny scale breath
        let breath = 1.0 + sin(t * 1.2) * 0.008

        ctx.saveGState()
        ctx.translateBy(x: w/2 + shakeX, y: h/2 + shakeY)
        ctx.scaleBy(x: breath, y: breath)

        // ── Draw image ─────────────────────────────────────────────────
        let size = min(w, h) * 0.92
        let rect = CGRect(x: -size/2, y: -size/2, width: size, height: size)

        if let img = brainImage {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            img.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
        }

        // ── Blink overlay ──────────────────────────────────────────────
        // Only draw when blinkPhase > 0
        if blinkPhase > 0.01 {
            drawBlink(ctx, imageRect: rect, phase: min(blinkPhase, 1.0))
        }

        ctx.restoreGState()
    }

    // MARK: - Blink

    /// Draws a skin-coloured eyelid droop over each eye.
    /// `phase` 0 = fully open, 1 = fully closed.
    private func drawBlink(_ ctx: CGContext, imageRect r: CGRect, phase: CGFloat) {
        // Eye positions are roughly at these fractions of the image rect
        // (tuned to match the character's face in the image)
        // Left eye centre (character's right eye as we view it)
        let lx = r.minX + r.width  * 0.385
        let ly = r.minY + r.height * 0.525
        // Right eye centre
        let rx = r.minX + r.width  * 0.545
        let ry = r.minY + r.height * 0.525

        let eyeW  = r.width * 0.115   // eye oval width
        let eyeH  = r.width * 0.105   // eye oval height
        let lidH  = eyeH * phase       // how far the lid droops

        // Eyelid colour matches the face skin (pink)
        let lidColor = NSColor(red: 0.96, green: 0.72, blue: 0.74, alpha: 0.97)

        for (ex, ey) in [(lx, ly), (rx, ry)] {
            // Lid rect covers top portion of the eye oval
            let lidRect = CGRect(
                x: ex - eyeW * 0.5,
                y: ey - eyeH * 0.1,       // start slightly above eye centre
                width: eyeW,
                height: lidH * 1.15
            )
            // Rounded pill shape for the lid
            let path = CGPath(roundedRect: lidRect,
                              cornerWidth: eyeW * 0.5,
                              cornerHeight: eyeH * 0.5,
                              transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(lidColor.cgColor)
            ctx.fillPath()
        }
    }
}
