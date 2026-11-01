import Foundation
import SiliciumShared

public enum Metric: String, CaseIterable, Sendable, Codable {
    case cpuPerf, cpuEff, gpu, memoryUsed, swap, diskUsed, diskRead, diskWrite
    case netDown, netUp, powerTotal, powerCPU, powerGPU, powerANE, powerDRAM
    case tempChip, tempBattery, batteryCharge, batteryWatts, batteryHealth, batteryCycles, rssi, thermal

    public static func value(_ m: Metric, in s: Snapshot) -> Double? {
        switch m {
        case .cpuPerf: s.cpu?.perfAverage
        case .cpuEff: s.cpu?.effAverage
        case .gpu: s.gpu?.utilization
        case .memoryUsed: s.memory?.usedFraction
        case .swap: s.memory.map { Double($0.swapUsedBytes) }
        case .diskUsed: s.disk?.usedFraction
        case .diskRead: s.disk?.readBytesPerSec
        case .diskWrite: s.disk?.writeBytesPerSec
        case .netDown: s.network?.downBytesPerSec
        case .netUp: s.network?.upBytesPerSec
        case .powerTotal: s.power?.total
        case .powerCPU: s.power?.cpuWatts
        case .powerGPU: s.power?.gpuWatts
        case .powerANE: s.power?.aneWatts
        case .powerDRAM: s.power?.dramWatts
        case .tempChip: s.temperatures?.chipC
        case .tempBattery: s.temperatures?.batteryC
        case .batteryCharge: s.battery?.chargeFraction
        case .batteryWatts: s.battery?.watts
        case .batteryHealth: s.battery?.maxCapacityFraction
        case .batteryCycles: s.battery.map { Double($0.cycleCount) }
        case .rssi: s.network?.rssi.map(Double.init)
        case .thermal: Double(s.thermal.rawValue)
        }
    }
}

public struct MetricPoint: Sendable, Equatable, Identifiable {
    public var date: Date
    public var value: Double
    public var id: Date { date }
    public init(date: Date, value: Double) { self.date = date; self.value = value }
}

/// Tampons circulaires en RAM (10 min par défaut) : alimentent les mini-graphiques de 60 s.
public struct MetricStore: Sendable {
    public let capacity: Int
    private var buffers: [Metric: [MetricPoint]] = [:]

    public init(capacity: Int = 600) { self.capacity = capacity }

    public mutating func append(_ s: Snapshot) {
        for m in Metric.allCases {
            guard let v = Metric.value(m, in: s) else { continue }
            var b = buffers[m, default: []]
            b.append(MetricPoint(date: s.date, value: v))
            if b.count > capacity { b.removeFirst(b.count - capacity) }
            buffers[m] = b
        }
    }

    public func series(_ m: Metric, last seconds: TimeInterval? = nil) -> [MetricPoint] {
        let b = buffers[m] ?? []
        guard let seconds, let end = b.last?.date else { return b }
        let cutoff = end.addingTimeInterval(-seconds)
        return b.filter { $0.date >= cutoff }
    }
}
