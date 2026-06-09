import AppKit
import Combine

final class DashboardViewController: NSViewController {
    private var monitor: SystemMonitor!
    private var cancellables = Set<AnyCancellable>()

    // Cards
    private let gpuCard    = MetricCardView()
    private let gpuTempCard = MetricCardView()
    private let cpuCard    = MetricCardView()
    private let cpuTempCard = MetricCardView()
    private let vramCard   = MetricCardView()
    private let ramCard    = MetricCardView()
    private let llmView    = LLMStatusView()

    override func loadView() {
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 280))
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

        let outerStack = NSStackView(views: [topStack, llmView])
        outerStack.orientation = .vertical
        outerStack.spacing = 6

        view.addSubview(outerStack)
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            outerStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            outerStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            outerStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            llmView.heightAnchor.constraint(equalToConstant: 28),
        ])

        monitor = SystemMonitor()
        monitor.$latest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snap in self?.update(snap) }
            .store(in: &cancellables)

        monitor.$history
            .receive(on: DispatchQueue.main)
            .sink { [weak self] history in self?.updateSparklines(history) }
            .store(in: &cancellables)
    }

    private func configureCards() {
        let green  = NSColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 1)
        let cyan   = NSColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 1)
        let orange = NSColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1)
        let purple = NSColor(red: 0.8, green: 0.4, blue: 1.0, alpha: 1)
        let blue   = NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 1)
        let yellow = NSColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1)

        gpuCard.configure(title: "GPU", color: green)
        gpuTempCard.configure(title: "GPU Temp °F", color: orange)
        cpuCard.configure(title: "CPU", color: cyan)
        cpuTempCard.configure(title: "CPU Temp °F", color: orange)
        vramCard.configure(title: "VRAM", color: purple)
        ramCard.configure(title: "RAM", color: blue)

        gpuTempCard.gaugeView.isTemperatureGauge = true
        cpuTempCard.gaugeView.isTemperatureGauge = true
    }

    private func update(_ snap: SystemSnapshot) {
        gpuCard.gaugeView.value = snap.gpuUtilization
        gpuCard.valueLabel.stringValue = "\(Int(snap.gpuUtilization * 100))%"

        if let t = snap.gpuTemperature {
            let tF = t * 9/5 + 32
            gpuTempCard.gaugeView.value = t / 110   // danger at ~110°C → red
            gpuTempCard.valueLabel.stringValue = String(format: "%.0f°F", tF)
        } else {
            gpuTempCard.valueLabel.stringValue = "—"
        }

        cpuCard.gaugeView.value = snap.cpuUtilization
        cpuCard.valueLabel.stringValue = "\(Int(snap.cpuUtilization * 100))%"

        if let t = snap.cpuTemperature {
            let tF = t * 9/5 + 32
            cpuTempCard.gaugeView.value = t / 110
            cpuTempCard.valueLabel.stringValue = String(format: "%.0f°F", tF)
        } else {
            cpuTempCard.valueLabel.stringValue = "—"
        }

        let vramFrac = snap.vramTotal > 0 ? Double(snap.vramUsed) / Double(snap.vramTotal) : 0
        vramCard.gaugeView.value = vramFrac
        vramCard.valueLabel.stringValue = formatBytes(snap.vramUsed)
        vramCard.subtitleLabel.stringValue = "/ \(formatBytes(snap.vramTotal))"

        let ramFrac = snap.ramTotal > 0 ? Double(snap.ramUsed) / Double(snap.ramTotal) : 0
        ramCard.gaugeView.value = ramFrac
        ramCard.valueLabel.stringValue = formatBytes(snap.ramUsed)
        ramCard.subtitleLabel.stringValue = "/ \(formatBytes(snap.ramTotal))"

        llmView.update(models: snap.llmModels)
    }

    private func updateSparklines(_ history: [SystemSnapshot]) {
        gpuCard.sparkline.values     = history.map { $0.gpuUtilization }
        gpuTempCard.sparkline.values = history.map { ($0.gpuTemperature ?? 0) / 100 }
        cpuCard.sparkline.values     = history.map { $0.cpuUtilization }
        cpuTempCard.sparkline.values = history.map { ($0.cpuTemperature ?? 0) / 100 }
        vramCard.sparkline.values    = history.map {
            $0.vramTotal > 0 ? Double($0.vramUsed) / Double($0.vramTotal) : 0
        }
        ramCard.sparkline.values     = history.map {
            $0.ramTotal > 0 ? Double($0.ramUsed) / Double($0.ramTotal) : 0
        }
    }

    private func formatBytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1fG", gb) }
        let mb = Double(b) / 1_048_576
        return String(format: "%.0fM", mb)
    }
}
