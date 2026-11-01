import Foundation
import SiliciumShared
import IOKit

/// Utilisation GPU via `AGXAccelerator.PerformanceStatistics`.
public final class GPUSampler: Sampler {
    public typealias Reading = GPUReading?
    public private(set) var coreCount: Int?
    public init() {}

    public func sample() throws -> GPUReading? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AGXAccelerator"))
        let service = svc != 0 ? svc : IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        if coreCount == nil, let n = IORegistryEntryCreateCFProperty(service, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
            coreCount = n.intValue
        }
        guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { return nil }
        let util = (stats["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0
        let alloc = (stats["Alloc system memory"] as? NSNumber)?.uint64Value ?? 0
        let inUse = (stats["In use system memory"] as? NSNumber)?.uint64Value ?? 0
        return GPUReading(utilization: clamp01(util / 100), allocatedBytes: alloc, inUseBytes: inUse)
    }
}
