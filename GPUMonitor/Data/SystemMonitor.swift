import Foundation
import Combine

final class SystemMonitor: ObservableObject {
    @Published private(set) var latest: SystemSnapshot = .zero
    @Published private(set) var history: [SystemSnapshot] = []

    var refreshInterval: TimeInterval = 1.0 {
        didSet { restart() }
    }

    private let gpu         = GPUStatsProvider()
    private let cpu         = CPUStatsProvider()
    private let memory      = MemoryStatsProvider()
    private let temperature = TemperatureProvider()
    private let llm         = LLMDetector()

    private var timer: Timer?
    private var buffer = CircularBuffer<SystemSnapshot>(capacity: 60)
    private let queue  = DispatchQueue(label: "com.gpumonitor.stats", qos: .utility)

    init() { start() }
    deinit { timer?.invalidate() }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer?.fire()
    }

    private func restart() { timer?.invalidate(); start() }

    private func poll() {
        queue.async { [weak self] in
            guard let self else { return }

            let gpuStats  = self.gpu.fetch()
            let cpuUtil   = self.cpu.fetch()
            let memStats  = self.memory.fetch()
            let temps     = self.temperature.fetch()
            let llmModels = self.llm.detect()

            let snapshot = SystemSnapshot(
                timestamp: Date(),
                gpuUtilization: gpuStats.utilization,
                gpuTemperature: temps.gpu,
                vramUsed: gpuStats.vramUsed,
                vramTotal: gpuStats.vramTotal,
                cpuUtilization: cpuUtil,
                cpuTemperature: temps.cpu,
                ramUsed: memStats.used,
                ramTotal: memStats.total,
                memoryPressure: memStats.pressure,
                llmModels: llmModels
            )

            DispatchQueue.main.async {
                self.buffer.append(snapshot)
                self.latest = snapshot
                self.history = self.buffer.toArray()
            }
        }
    }
}
