import Foundation
import SiliciumShared
import Darwin

/// Mémoire, swap et pression, calculés comme le Moniteur d'activité.
public final class MemorySampler: Sampler {
    public typealias Reading = MemoryReading
    private let total: UInt64
    private let pageSize: UInt64

    public init() {
        var size: UInt64 = 0; var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        total = size
        pageSize = UInt64(getpagesize())
    }

    public func sample() throws -> MemoryReading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { throw SamplerError.unavailable("host_statistics64") }
        let ps = pageSize
        let app = (UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)) * ps
        let wired = UInt64(stats.wire_count) * ps
        let compressed = UInt64(stats.compressor_page_count) * ps
        let cached = (UInt64(stats.external_page_count) + UInt64(stats.purgeable_count)) * ps
        let used = min(total, app + wired + compressed)

        var swap = xsw_usage(); var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        var level: Int32 = 1; var lsize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &lsize, nil, 0)
        let pressure = MemoryPressure(rawValue: Int(level)) ?? .normal

        return MemoryReading(totalBytes: total, usedBytes: used, appBytes: app, wiredBytes: wired,
                             compressedBytes: compressed, cachedBytes: cached,
                             swapUsedBytes: swap.xsu_used, pressure: pressure)
    }
}
