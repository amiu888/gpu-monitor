import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private var dashVC: DashboardViewController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var isPanelVisible = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        let vc = DashboardViewController()
        dashVC = vc

        // ── Floating panel ──────────────────────────────────────────
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
        panel.contentView?.menu = buildContextMenu()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification, object: panel)
        self.panel = panel

        // ── Menu bar status item ─────────────────────────────────────
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let btn = statusItem?.button {
            btn.title = "GPU –%"
            btn.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
            btn.action = #selector(statusBarClicked)
            btn.target = self
        }

        // Subscribe to GPU % for live status bar readout
        vc.monitor.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in
                let pct = Int(snap.gpuUtilization * 100)
                self?.statusItem?.button?.title = "GPU \(pct)%"
            }
            .store(in: &cancellables)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Status bar toggle

    @objc private func statusBarClicked() {
        guard let panel else { return }
        if isPanelVisible {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        isPanelVisible.toggle()
    }

    // MARK: - Context Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        let rateMenu = NSMenu()
        for (title, interval) in [("0.5s", 0.5), ("1s (default)", 1.0), ("2s", 2.0)] {
            let item = NSMenuItem(title: title, action: #selector(setRefreshRate(_:)), keyEquivalent: "")
            item.representedObject = interval; item.target = self
            rateMenu.addItem(item)
        }
        let rateItem = NSMenuItem(title: "Refresh Rate", action: nil, keyEquivalent: "")
        rateItem.submenu = rateMenu

        let opacityMenu = NSMenu()
        for (title, alpha) in [("100%", 1.0), ("80%", 0.8), ("60%", 0.6), ("40%", 0.4)] {
            let item = NSMenuItem(title: title, action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.representedObject = alpha; item.target = self
            opacityMenu.addItem(item)
        }
        let opacityItem = NSMenuItem(title: "Opacity", action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu

        menu.addItem(rateItem)
        menu.addItem(opacityItem)
        menu.addItem(.separator())
        let ssItem = NSMenuItem(title: "▶  Start Screen Saver", action: #selector(startScreenSaver), keyEquivalent: "s")
        ssItem.target = self
        menu.addItem(ssItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit GPU Monitor",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        return menu
    }

    @objc func startScreenSaver() {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
    }

    @objc private func setRefreshRate(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? Double else { return }
        dashVC?.monitor.refreshInterval = interval
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
        let w: CGFloat = 760, h: CGFloat = 280
        return NSRect(x: visible.maxX - w - 20, y: visible.maxY - h - 20, width: w, height: h)
    }

    private func savedFrame() -> NSRect? {
        guard let s = UserDefaults.standard.string(forKey: "panelFrame") else { return nil }
        let r = NSRectFromString(s); return r == .zero ? nil : r
    }
}
