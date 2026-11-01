import Foundation
import SiliciumShared
import Darwin

/// Charge CPU par cœur via `host_processor_info` (delta de ticks).
public final class CPUSampler: Sampler {
    public typealias Reading = CPUReading
    private var previous: [[UInt32]] = []
    public let perfIndices: [Int]
    public let effIndices: [Int]

    public init() {
        let nPerf = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        let nEff = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        let total = Self.sysctlInt("hw.logicalcpu") ?? (nPerf + nEff)
        if nPerf + nEff == total, nPerf > 0, nEff > 0 {
            // Sur Apple Silicon, les cœurs d'efficacité sont indexés en premier.
            effIndices = Array(0..<nEff)
            perfIndices = Array(nEff..<total)
        } else {
            effIndices = []
            perfIndices = Array(0..<total)
        }
    }

    static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0; var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
    }

    private func ticks() throws -> [[UInt32]] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let r = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount)
        guard r == KERN_SUCCESS, let info else { throw SamplerError.unavailable("host_processor_info") }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)) }
        var out: [[UInt32]] = []
        let stride = Int(CPU_STATE_MAX)
        for i in 0..<Int(count) {
            let base = i * stride
            out.append([UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                        UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                        UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                        UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])])
        }
        return out
    }

    public func sample() throws -> CPUReading {
        let now = try ticks()
        defer { previous = now }
        guard previous.count == now.count else {
            return CPUReading(perfLoad: Array(repeating: 0, count: perfIndices.count),
                              effLoad: Array(repeating: 0, count: effIndices.count))
        }
        var loads: [Double] = []
        for i in 0..<now.count {
            let d = (0..<4).map { now[i][$0] &- previous[i][$0] }
            let busy = Double(d[0]) + Double(d[1]) + Double(d[3])
            let total = busy + Double(d[2])
            loads.append(total > 0 ? busy / total : 0)
        }
        return CPUReading(perfLoad: perfIndices.compactMap { $0 < loads.count ? loads[$0] : nil },
                          effLoad: effIndices.compactMap { $0 < loads.count ? loads[$0] : nil })
    }
}
