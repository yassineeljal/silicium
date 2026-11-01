import Foundation
import SiliciumShared
import IOKit

/// Espace disque (API publique) + débit via `IOBlockStorageDriver` + SMART NVMe (si disponible).
public final class DiskSampler: Sampler {
    public typealias Reading = DiskReading
    private var last: (date: Double, read: UInt64, write: UInt64)?
    private var cachedSpace: (date: Double, total: UInt64, free: UInt64)?
    private var cachedSmart: (date: Double, warning: Bool?, wear: Double?, temp: Double?)?

    public init() {}

    private func space() -> (UInt64, UInt64) {
        let now = monotonicSeconds()
        if let c = cachedSpace, now - c.date < 60 { return (c.total, c.free) }
        let url = URL(fileURLWithPath: "/")
        let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let total = UInt64(v?.volumeTotalCapacity ?? 0)
        let free = UInt64(max(0, v?.volumeAvailableCapacityForImportantUsage ?? 0))
        cachedSpace = (now, total, free)
        return (total, free)
    }

    private func ioStats() -> (read: UInt64, write: UInt64) {
        var read: UInt64 = 0, write: UInt64 = 0
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &it) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(it) }
        while case let svc = IOIteratorNext(it), svc != 0 {
            defer { IOObjectRelease(svc) }
            if let dict = IORegistryEntryCreateCFProperty(svc, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                read += (dict["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (dict["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
        }
        return (read, write)
    }

    /// Lit la santé NVMe exposée dans l'IORegistry (`NVMe SMART Capable` + `Device Characteristics`).
    private func smart() -> (Bool?, Double?, Double?) {
        let now = monotonicSeconds()
        if let c = cachedSmart, now - c.date < 300 { return (c.warning, c.wear, c.temp) }
        var warning: Bool?, wear: Double?, temp: Double?
        var it: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleANS3NVMeController"), &it) == KERN_SUCCESS {
            defer { IOObjectRelease(it) }
            while case let svc = IOIteratorNext(it), svc != 0 {
                defer { IOObjectRelease(svc) }
                if let d = IORegistryEntryCreateCFProperty(svc, "SMART Data" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                    if let cw = (d["Critical Warning"] as? NSNumber)?.intValue { warning = cw != 0 }
                    if let used = (d["Percentage Used"] as? NSNumber)?.doubleValue { wear = used }
                    if let t = (d["Temperature"] as? NSNumber)?.doubleValue { temp = t > 200 ? t - 273.15 : t }
                }
            }
        }
        cachedSmart = (now, warning, wear, temp)
        return (warning, wear, temp)
    }

    public func sample() throws -> DiskReading {
        let now = monotonicSeconds()
        let (total, free) = space()
        let io = ioStats()
        var r = 0.0, w = 0.0
        if let l = last, now > l.date {
            let dt = now - l.date
            r = io.read >= l.read ? Double(io.read - l.read) / dt : 0
            w = io.write >= l.write ? Double(io.write - l.write) / dt : 0
        }
        last = (now, io.read, io.write)
        let s = smart()
        return DiskReading(totalBytes: total, freeBytes: free, readBytesPerSec: r, writeBytesPerSec: w,
                           smartCriticalWarning: s.0, wearPercent: s.1, temperatureC: s.2)
    }
}
