import Foundation
import Darwin.Mach

final class CPUStatsProvider {
    private var prevInfo: [processor_cpu_load_info_data_t] = []

    func fetch() -> Double {
        var cpuCount: natural_t = 0
        var infoCount: mach_msg_type_number_t = 0
        var infoArray: processor_info_array_t?

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &infoArray,
            &infoCount
        )
        guard kr == KERN_SUCCESS, let infoArray else { return 0 }
        defer {
            let size = Int(infoCount) * MemoryLayout<integer_t>.size
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: infoArray), vm_size_t(size))
        }

        let cpuLoad = infoArray.withMemoryRebound(
            to: processor_cpu_load_info_data_t.self,
            capacity: Int(cpuCount)
        ) { ptr -> [processor_cpu_load_info_data_t] in
            (0..<Int(cpuCount)).map { ptr[$0] }
        }
        _ = infoCount

        guard !prevInfo.isEmpty, prevInfo.count == cpuLoad.count else {
            prevInfo = cpuLoad
            return 0
        }

        var totalUser: UInt32 = 0, totalSystem: UInt32 = 0
        var totalIdle: UInt32 = 0, totalNice: UInt32 = 0

        for i in 0..<cpuLoad.count {
            let cur = cpuLoad[i].cpu_ticks
            let prv = prevInfo[i].cpu_ticks
            totalUser   += cur.0 &- prv.0
            totalSystem += cur.1 &- prv.1
            totalIdle   += cur.2 &- prv.2
            totalNice   += cur.3 &- prv.3
        }

        prevInfo = cpuLoad

        let total = Double(totalUser + totalSystem + totalIdle + totalNice)
        guard total > 0 else { return 0 }
        return Double(totalUser + totalSystem) / total
    }
}
