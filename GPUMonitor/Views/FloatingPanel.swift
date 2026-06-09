import AppKit

final class FloatingPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        setup()
    }

    private func setup() {
        level = .floating
        backgroundColor = NSColor(white: 0.08, alpha: 0.92)
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        acceptsMouseMovedEvents = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        // Rounded corners via content view layer
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 12
        contentView?.layer?.masksToBounds = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Allow dragging from anywhere in the window
    override func mouseDown(with event: NSEvent) {
        performDrag(with: event)
    }
}
