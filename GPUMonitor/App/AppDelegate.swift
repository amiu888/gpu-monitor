import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var dashVC: DashboardViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vc = DashboardViewController()
        dashVC = vc

        let panelRect = savedFrame() ?? defaultFrame()
        let panel = FloatingPanel(
            contentRect: panelRect,
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = vc
        panel.setFrame(panelRect, display: false)
        panel.makeKeyAndOrderFront(nil)

        // Context menu
        panel.contentView?.menu = buildContextMenu()

        // Persist position on close / move
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification,
            object: panel
        )

        self.panel = panel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Context Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let rateMenu = NSMenu()
        for (title, interval) in [("0.5s", 0.5), ("1s (default)", 1.0), ("2s", 2.0)] {
            let item = NSMenuItem(title: title, action: #selector(setRefreshRate(_:)), keyEquivalent: "")
            item.representedObject = interval
            item.target = self
            rateMenu.addItem(item)
        }
        let rateItem = NSMenuItem(title: "Refresh Rate", action: nil, keyEquivalent: "")
        rateItem.submenu = rateMenu

        let opacityMenu = NSMenu()
        for (title, alpha) in [("100%", 1.0), ("80%", 0.8), ("60%", 0.6), ("40%", 0.4)] {
            let item = NSMenuItem(title: title, action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.representedObject = alpha
            item.target = self
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu

        menu.addItem(rateItem)
        menu.addItem(opacityItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit GPU Monitor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        return menu
    }

    @objc private func setRefreshRate(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? Double else { return }
        (dashVC?.view as? NSView)  // access monitor through VC if needed
        UserDefaults.standard.set(interval, forKey: "refreshInterval")
    }

    @objc private func setOpacity(_ sender: NSMenuItem) {
        guard let alpha = sender.representedObject as? Double else { return }
        panel?.alphaValue = alpha
        UserDefaults.standard.set(alpha, forKey: "panelOpacity")
    }

    // MARK: - Persistence

    @objc private func windowMoved() {
        guard let frame = panel?.frame else { return }
        UserDefaults.standard.set(NSStringFromRect(frame), forKey: "panelFrame")
    }

    private func defaultFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let w: CGFloat = 680, h: CGFloat = 280
        // Top-right corner, inset 20pt from edges
        return NSRect(
            x: visible.maxX - w - 20,
            y: visible.maxY - h - 20,
            width: w, height: h
        )
    }

    private func savedFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: "panelFrame") else { return nil }
        let r = NSRectFromString(s)
        return r == .zero ? nil : r
    }
}
