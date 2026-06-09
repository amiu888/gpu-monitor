import Foundation
import AppKit
import Darwin.sys.sysctl

final class LLMDetector {
    private let ollamaCandidates = [
        "/usr/local/bin/ollama",
        "/opt/homebrew/bin/ollama",
        "/Applications/Ollama.app/Contents/Resources/ollama"
    ]

    func detect() -> [LLMEntry] {
        // If ollama daemon is running, use `ollama ps` for full model info
        if sysctlHasProcess("ollama") {
            let models = parseOllamaPS()
            if !models.isEmpty { return models }
            // Daemon running but no models loaded
            return [LLMEntry(name: "ollama", processor: "idle", size: "")]
        }
        // Fallback: other known LLM process names
        for name in ["llama-server", "llama-cli", "llamafile", "mlx_lm"] {
            if sysctlHasProcess(name) {
                return [LLMEntry(name: name, processor: "running", size: "")]
            }
        }
        // GUI apps
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier, bid == "com.lmstudio.app" {
                return [LLMEntry(name: app.localizedName ?? "LM Studio", processor: "running", size: "")]
            }
        }
        return []
    }

    // Parses `ollama ps` output → array of LLMEntry
    private func parseOllamaPS() -> [LLMEntry] {
        guard let path = ollamaPath(),
              let raw = shellOutput(path, ["ps"]),
              !raw.isEmpty else { return [] }

        // Header: NAME  ID  SIZE  PROCESSOR  CONTEXT  UNTIL
        let lines = raw.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard lines.count > 1 else { return [] }

        // Find column offsets from header
        let header = lines[0]
        let nameIdx    = header.range(of: "NAME")?.lowerBound
        let sizeIdx    = header.range(of: "SIZE")?.lowerBound
        let procIdx    = header.range(of: "PROCESSOR")?.lowerBound
        let contextIdx = header.range(of: "CONTEXT")?.lowerBound

        var results: [LLMEntry] = []
        for line in lines.dropFirst() {
            let cols = splitColumns(line, header: header,
                                    starts: [nameIdx, sizeIdx, procIdx, contextIdx])
            guard cols.count >= 3 else { continue }
            let name = cols[0].trimmingCharacters(in: .whitespaces)
            let size = cols[1].trimmingCharacters(in: .whitespaces)
            let proc = cols[2].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                results.append(LLMEntry(name: name, processor: proc, size: size))
            }
        }
        return results
    }

    // Split a line into columns using header start positions
    private func splitColumns(_ line: String, header: String, starts: [String.Index?]) -> [String] {
        let validStarts = starts.compactMap { $0 }
        guard !validStarts.isEmpty else {
            return line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        }
        var cols: [String] = []
        for (i, start) in validStarts.enumerated() {
            let lineStart = line.index(line.startIndex, offsetBy: header.distance(from: header.startIndex, to: start), limitedBy: line.endIndex) ?? line.endIndex
            let lineEnd: String.Index
            if i + 1 < validStarts.count {
                let nextStart = validStarts[i + 1]
                lineEnd = line.index(line.startIndex, offsetBy: header.distance(from: header.startIndex, to: nextStart), limitedBy: line.endIndex) ?? line.endIndex
            } else {
                lineEnd = line.endIndex
            }
            if lineStart <= lineEnd {
                cols.append(String(line[lineStart..<lineEnd]))
            }
        }
        return cols
    }

    private func ollamaPath() -> String? {
        for p in ollamaCandidates where FileManager.default.isExecutableFile(atPath: p) { return p }
        return shellOutput("/usr/bin/which", ["ollama"])?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    private func shellOutput(_ path: String, _ args: [String]) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(2)
        while task.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if task.isRunning { task.terminate(); return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }

    private func sysctlHasProcess(_ needle: String) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var sz: Int = 0
        guard sysctl(&mib, 4, nil, &sz, nil, 0) == 0, sz > 0 else { return false }
        let count = sz / MemoryLayout<kinfo_proc>.stride
        var list = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &list, &sz, nil, 0) == 0 else { return false }
        let actual = sz / MemoryLayout<kinfo_proc>.stride
        for i in 0..<actual {
            let name = withUnsafePointer(to: list[i].kp_proc.p_comm) { ptr -> String in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { String(cString: $0) }
            }
            if name.contains(needle) { return true }
        }
        return false
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
