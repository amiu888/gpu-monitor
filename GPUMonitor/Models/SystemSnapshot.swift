import Foundation

struct LLMEntry {
    let name: String       // e.g. "qwen3.6-hermes:latest"
    let processor: String  // e.g. "100% GPU"
    let size: String       // e.g. "27 GB"
}

struct SystemSnapshot {
    let timestamp: Date
    let gpuUtilization: Double      // 0.0–1.0
    let gpuTemperature: Double?     // °C
    let vramUsed: UInt64
    let vramTotal: UInt64
    let cpuUtilization: Double      // 0.0–1.0
    let cpuTemperature: Double?     // °C
    let ramUsed: UInt64
    let ramTotal: UInt64
    let memoryPressure: Double      // 0.0–1.0
    let llmModels: [LLMEntry]

    static let zero = SystemSnapshot(
        timestamp: .distantPast,
        gpuUtilization: 0, gpuTemperature: nil,
        vramUsed: 0, vramTotal: 1,
        cpuUtilization: 0, cpuTemperature: nil,
        ramUsed: 0, ramTotal: 1,
        memoryPressure: 0, llmModels: []
    )
}
