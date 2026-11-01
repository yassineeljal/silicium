import Foundation
import SiliciumShared
import IOKit

/// Puissance CPU / GPU / ANE / DRAM (W) et fréquences par grappe via IOReport.
public final class PowerSampler: Sampler {
    public struct Output: Sendable {
        public var power: PowerReading?
        public var perfFreqMHz: Double?
        public var effFreqMHz: Double?
        public var gpuFreqMHz: Double?
        public init(power: PowerReading? = nil, perfFreqMHz: Double? = nil, effFreqMHz: Double? = nil, gpuFreqMHz: Double? = nil) {
            self.power = power; self.perfFreqMHz = perfFreqMHz; self.effFreqMHz = effFreqMHz; self.gpuFreqMHz = gpuFreqMHz
        }
    }
    public typealias Reading = Output

    private let sub: IOReportSubscription?
    private let freqTables: FrequencyTables

    public init() {
        sub = IOReportSubscription(groups: [("Energy Model", nil), ("CPU Stats", "CPU Core Performance States"), ("GPU Stats", "GPU Performance States")])
        freqTables = FrequencyTables.load()
    }

    public var isAvailable: Bool { sub != nil }

    private static func joules(_ v: Int64, unit: String) -> Double {
        switch unit {
        case "mJ": Double(v) / 1e3
        case "uJ", "µJ": Double(v) / 1e6
        case "nJ": Double(v) / 1e9
        default: Double(v) / 1e6
        }
    }

    public func sample() throws -> Output {
        guard let sub else { throw SamplerError.unavailable("IOReport") }
        guard let (channels, dt) = sub.sampleDelta() else { return Output() }
        var cpu = 0.0, gpu = 0.0, ane = 0.0, dram = 0.0
        var found = false
        var pw = 0.0, pt = 0.0, ew = 0.0, et = 0.0, gw = 0.0, gt = 0.0
        for ch in channels {
            if ch.group == "Energy Model" {
                let w = Self.joules(ch.value, unit: ch.unit) / dt
                let n = ch.name
                if n == "CPU Energy" || (n.hasSuffix("CPU Energy") && !n.contains("GPU")) { cpu += w; found = true }
                else if n == "GPU Energy" { gpu += w; found = true }
                else if n.hasPrefix("ANE") { ane += w; found = true }
                else if n.hasPrefix("DRAM") { dram += w; found = true }
            } else if ch.group == "CPU Stats" {
                guard let f = freqTables.frequency(channel: ch.name, states: ch.states) else { continue }
                if ch.name.hasPrefix("E") { ew += f.weighted; et += f.total }
                else { pw += f.weighted; pt += f.total }
            } else if ch.group == "GPU Stats", ch.name.hasPrefix("GPUPH") {
                if let f = freqTables.frequency(channel: ch.name, states: ch.states) { gw += f.weighted; gt += f.total }
            }
        }
        return Output(power: found ? PowerReading(cpuWatts: cpu, gpuWatts: gpu, aneWatts: ane, dramWatts: dram) : nil,
                      perfFreqMHz: pt > 0 ? pw / pt : nil, effFreqMHz: et > 0 ? ew / et : nil, gpuFreqMHz: gt > 0 ? gw / gt : nil)
    }

    /// Pour la cartographie / le debug : liste brute des canaux.
    public func debugChannels() -> [String] {
        guard let sub, let (chs, _) = sub.sampleDelta() else { return [] }
        return chs.map { "\($0.group) | \($0.subGroup) | \($0.name) | \($0.unit) | \($0.value) | states=\($0.states.map { "\($0.name):\($0.residency)" }.joined(separator: ","))" }
    }
}

/// Fréquences : les états IOReport sont nommés `V<i>P<j>` où `i` indexe la table DVFS du `pmgr`
/// (`voltage-states*-sram` pour les CPU, `voltage-states9` pour le GPU).
struct FrequencyTables: Sendable {
    var cpuTables: [[Double]]   // en MHz, triées par taille
    var gpuTable: [Double]

    static func load() -> FrequencyTables {
        var cpu: [[Double]] = []; var gpu: [Double] = []
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"))
        guard svc != 0 else { return FrequencyTables(cpuTables: [], gpuTable: []) }
        defer { IOObjectRelease(svc) }
        func table(_ key: String) -> [Double]? {
            guard let data = IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Data,
                  data.count >= 8 else { return nil }
            return stride(from: 0, to: data.count - 7, by: 8).map { off in
                let raw = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt32.self) }
                let v = Double(raw)
                return v > 1e8 ? v / 1e6 : v / 1e3     // Hz → MHz, kHz → MHz
            }
        }
        for k in ["voltage-states1-sram", "voltage-states5-sram", "voltage-states13-sram", "voltage-states7-sram"] {
            if let t = table(k) { cpu.append(t) }
        }
        if let g = table("voltage-states9") { gpu = g }
        return FrequencyTables(cpuTables: cpu, gpuTable: gpu)
    }

    /// Fréquence moyenne pondérée par la résidence active, pour un canal (cœur ou GPU).
    func frequency(channel: String, states: [(name: String, residency: Int64)]) -> (weighted: Double, total: Double)? {
        let active = states.filter { $0.name.hasPrefix("V") || $0.name.hasPrefix("P") }
        guard !active.isEmpty else { return nil }
        let isGPU = channel.hasPrefix("GPU")
        let table: [Double]
        if isGPU { table = gpuTable } else {
            guard let t = cpuTables.first(where: { $0.count == active.count }) else { return nil }
            table = t
        }
        guard !table.isEmpty else { return nil }
        var weighted = 0.0, total = 0.0
        for (i, st) in active.enumerated() {
            let digits = st.name.dropFirst().prefix { $0.isNumber }
            var idx = Int(digits) ?? i
            if isGPU { idx = max(0, idx - 1) }
            let mhz = table[min(idx, table.count - 1)]
            weighted += mhz * Double(st.residency); total += Double(st.residency)
        }
        return (weighted, total)
    }
}
