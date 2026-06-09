import Foundation
import IOKit

struct GPUStats {
    var utilization: Double = 0   // 0.0–1.0
    var vramUsed: UInt64 = 0
    var vramTotal: UInt64 = 0
}

final class GPUStatsProvider {
    func fetch() -> GPUStats {
        var stats = GPUStats()

        // Get total system RAM as vramTotal for Apple Silicon unified memory
        let totalRam = ProcessInfo.processInfo.physicalMemory
        stats.vramTotal = totalRam

        var iter: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iter) == KERN_SUCCESS else {
            return stats
        }
        defer { IOObjectRelease(iter) }

        var service = IOIteratorNext(iter)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }

            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any] else { continue }

            // Performance statistics are nested under "PerformanceStatistics"
            guard let perfStats = dict["PerformanceStatistics"] as? [String: Any] else { continue }

            // GPU core utilization
            if let util = perfStats["Device Utilization %"] as? Int {
                stats.utilization = Double(util) / 100.0
            } else if let util = perfStats["GPU Activity(%)"] as? Int {
                stats.utilization = Double(util) / 100.0
            }

            // Apple Silicon: shared memory usage (IOKit returns NSNumber, cast via Int64)
            if let inUse = (perfStats["In use system memory"] as? NSNumber)?.uint64Value {
                stats.vramUsed = inUse
            } else if let inUse = (perfStats["vramUsedBytes"] as? NSNumber)?.uint64Value {
                stats.vramUsed = inUse
            }
            if let free = (perfStats["vramFreeBytes"] as? NSNumber)?.uint64Value {
                stats.vramTotal = stats.vramUsed + free
            }

            // Use first accelerator found
            if stats.utilization > 0 { break }
        }

        return stats
    }
}
