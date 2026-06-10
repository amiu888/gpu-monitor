import AppKit
import Combine

final class DashboardViewController: NSViewController {
    // Exposed so AppDelegate can subscribe for the menu-bar readout
    let monitor = SystemMonitor()
    private var cancellables = Set<AnyCancellable>()

    // Small brain in the corner
    private let brainView   = BrainAnimationView()
    private var brainTimer: Timer?

    // Cards
    private let gpuCard     = MetricCardView()
    private let gpuTempCard = MetricCardView()
    private let cpuCard     = MetricCardView()
    private let cpuTempCard = MetricCardView()
    private let vramCard    = MetricCardView()
    private let ramCard     = MetricCardView()
    private let llmView     = LLMStatusView()

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 280))
        v.wantsLayer = true
        self.view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureCards()

        let topStack = NSStackView(views: [gpuCard, gpuTempCard, cpuCard, cpuTempCard, vramCard, ramCard])
        topStack.orientation = .horizontal
        topStack.distribution = .fillEqually
        topStack.spacing = 8

        // Screen Saver button
        let ssBtn = makeSSButton()

        // Bottom bar: LLM status + SS button
        let bottomBar = NSStackView(views: [llmView, ssBtn])
        bottomBar.orientation = .horizontal
        bottomBar.spacing = 8
        bottomBar.alignment = .centerY

        let outerStack = NSStackView(views: [topStack, bottomBar])
        outerStack.orientation = .vertical
        outerStack.spacing = 6

        // ── Brain view (right side, full height) ────────────────────
        brainView.wantsLayer = true
        brainView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(outerStack)
        view.addSubview(brainView)
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        // Close button — top-left corner, macOS traffic-light style
        let closeBtn = makeCloseButton()
        view.addSubview(closeBtn)

        let brainW: CGFloat = 200

        NSLayoutConstraint.activate([
            // Brain on the right
            brainView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            brainView.topAnchor.constraint(equalTo: view.topAnchor),
            brainView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            brainView.widthAnchor.constraint(equalToConstant: brainW),

            // Cards take the remaining left width
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            outerStack.trailingAnchor.constraint(equalTo: brainView.leadingAnchor, constant: -6),
            outerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            outerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            bottomBar.heightAnchor.constraint(equalToConstant: 28),
            ssBtn.widthAnchor.constraint(equalToConstant: 120),
            closeBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            closeBtn.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            closeBtn.widthAnchor.constraint(equalToConstant: 14),
            closeBtn.heightAnchor.constraint(equalToConstant: 14),
        ])

        monitor.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in self?.update(snap) }
            .store(in: &cancellables)

        monitor.$history
            .receive(on: DispatchQueue.main)
            .sink { [weak self] history in self?.updateSparklines(history) }
            .store(in: &cancellables)

        // 60 fps brain animation timer
        brainTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.brainView.advance(by: 1.0/60.0)
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        brainTimer?.invalidate()
    }

    // MARK: - Close button

    private func makeCloseButton() -> NSView {
        let btn = NSButton(frame: .zero)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.bezelStyle = .circular
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 7
        btn.layer?.backgroundColor = NSColor(red: 1, green: 0.37, blue: 0.34, alpha: 1).cgColor
        btn.title = ""
        btn.target = self
        btn.action = #selector(closePanel)

        // Draw the × symbol on hover via tracking area
        btn.toolTip = "Close"
        return btn
    }

    @objc private func closePanel() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Screen Saver button

    private func makeSSButton() -> NSButton {
        let btn = NSButton(title: "▶  Screen Saver", target: self, action: #selector(launchScreenSaver))
        btn.bezelStyle = .rounded
        btn.font = .systemFont(ofSize: 10, weight: .medium)
        btn.contentTintColor = NSColor(red: 0.3, green: 0.8, blue: 1, alpha: 1)
        return btn
    }

    @objc private func launchScreenSaver() {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
    }

    // MARK: - Card setup

    private func configureCards() {
        let green  = NSColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 1)
        let cyan   = NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1)
        let orange = NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        let purple = NSColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1)
        let blue   = NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)

        gpuCard.configure(title: "GPU",        color: green)
        gpuTempCard.configure(title: "GPU °F", color: orange)
        cpuCard.configure(title: "CPU",        color: cyan)
        cpuTempCard.configure(title: "CPU °F", color: orange)
        vramCard.configure(title: "VRAM",      color: purple)
        ramCard.configure(title: "RAM",        color: blue)

        gpuTempCard.gaugeView.isTemperatureGauge = true
        cpuTempCard.gaugeView.isTemperatureGauge = true
    }

    // MARK: - Updates

    private func update(_ snap: SystemSnapshot) {
        // Feed brain animation
        brainView.gpuLoad  = CGFloat(snap.gpuUtilization)
        brainView.cpuLoad  = CGFloat(snap.cpuUtilization)
        brainView.llmOnGPU = snap.llmModels.first?.processor.lowercased().contains("gpu") == true
        brainView.llmOnCPU = snap.llmModels.first?.processor.lowercased().contains("cpu") == true

        gpuCard.gaugeView.value = snap.gpuUtilization
        gpuCard.valueLabel.stringValue = "\(Int(snap.gpuUtilization * 100))%"

        if let t = snap.gpuTemperature {
            gpuTempCard.gaugeView.value = t / 110
            gpuTempCard.valueLabel.stringValue = String(format: "%.0f°F", t * 9/5 + 32)
        } else {
            gpuTempCard.valueLabel.stringValue = "—"
        }

        cpuCard.gaugeView.value = snap.cpuUtilization
        cpuCard.valueLabel.stringValue = "\(Int(snap.cpuUtilization * 100))%"

        if let t = snap.cpuTemperature {
            cpuTempCard.gaugeView.value = t / 110
            cpuTempCard.valueLabel.stringValue = String(format: "%.0f°F", t * 9/5 + 32)
        } else {
            cpuTempCard.valueLabel.stringValue = "—"
        }

        let vramFrac = snap.vramTotal > 0 ? Double(snap.vramUsed) / Double(snap.vramTotal) : 0
        vramCard.gaugeView.value = vramFrac
        vramCard.valueLabel.stringValue    = formatBytes(snap.vramUsed)
        vramCard.subtitleLabel.stringValue = "/ \(formatBytes(snap.vramTotal))"

        let ramFrac = snap.ramTotal > 0 ? Double(snap.ramUsed) / Double(snap.ramTotal) : 0
        ramCard.gaugeView.value = ramFrac
        ramCard.valueLabel.stringValue    = formatBytes(snap.ramUsed)
        ramCard.subtitleLabel.stringValue = "/ \(formatBytes(snap.ramTotal))"

        llmView.update(models: snap.llmModels)
    }

    private func updateSparklines(_ history: [SystemSnapshot]) {
        gpuCard.sparkline.values     = history.map { $0.gpuUtilization }
        gpuTempCard.sparkline.values = history.map { ($0.gpuTemperature ?? 0) / 100 }
        cpuCard.sparkline.values     = history.map { $0.cpuUtilization }
        cpuTempCard.sparkline.values = history.map { ($0.cpuTemperature ?? 0) / 100 }
        vramCard.sparkline.values    = history.map {
            $0.vramTotal > 0 ? Double($0.vramUsed) / Double($0.vramTotal) : 0 }
        ramCard.sparkline.values     = history.map {
            $0.ramTotal > 0 ? Double($0.ramUsed) / Double($0.ramTotal) : 0 }
    }

    private func formatBytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1fG", gb) }
        return String(format: "%.0fM", Double(b) / 1_048_576)
    }
}
