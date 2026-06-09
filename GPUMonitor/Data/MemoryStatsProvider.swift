import Foundation
import Darwin.Mach

struct MemoryStats {
    var used: UInt64
    var total: UInt64
    var pressure: Double  // 0.0–1.0
}

final class MemoryStatsProvider {
    func fetch() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory

        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)

        let kr = withUnsafeMutablePointer(to: &vmStats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            return MemoryStats(used: 0, total: total, pressure: 0)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active   = UInt64(vmStats.active_count) * pageSize
        let wired    = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let used     = active + wired + compressed

        // Memory pressure: used / total; but also factor in compressor growth
        let pressure = min(Double(used) / Double(total), 1.0)

        return MemoryStats(used: min(used, total), total: total, pressure: pressure)
    }
}
