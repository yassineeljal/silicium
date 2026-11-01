import Foundation

public enum ThermalPressure: Int, Sendable, Codable, Comparable {
    case nominal = 0, moderate, heavy, critical
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var label: String {
        switch self {
        case .nominal: "Nominale"
        case .moderate: "Modérée"
        case .heavy: "Forte"
        case .critical: "Critique"
        }
    }
}

public enum MemoryPressure: Int, Sendable, Codable, Comparable {
    case normal = 1, warning = 2, critical = 4
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var label: String {
        switch self {
        case .normal: "Normale"
        case .warning: "Avertissement"
        case .critical: "Critique"
        }
    }
}

public struct CPUReading: Sendable, Codable, Equatable {
    /// Charge 0…1 par cœur logique, dans l'ordre de `perfCoreIndices` / `effCoreIndices`.
    public var perfLoad: [Double]
    public var effLoad: [Double]
    public var perfFrequencyMHz: Double?
    public var effFrequencyMHz: Double?
    public init(perfLoad: [Double], effLoad: [Double], perfFrequencyMHz: Double? = nil, effFrequencyMHz: Double? = nil) {
        self.perfLoad = perfLoad; self.effLoad = effLoad
        self.perfFrequencyMHz = perfFrequencyMHz; self.effFrequencyMHz = effFrequencyMHz
    }
    public var perfAverage: Double { perfLoad.isEmpty ? 0 : perfLoad.reduce(0, +) / Double(perfLoad.count) }
    public var effAverage: Double { effLoad.isEmpty ? 0 : effLoad.reduce(0, +) / Double(effLoad.count) }
    public var overall: Double {
        let all = perfLoad + effLoad
        return all.isEmpty ? 0 : all.reduce(0, +) / Double(all.count)
    }
}

public struct GPUReading: Sendable, Codable, Equatable {
    public var utilization: Double          // 0…1
    public var allocatedBytes: UInt64
    public var inUseBytes: UInt64
    public var frequencyMHz: Double?
    public init(utilization: Double, allocatedBytes: UInt64, inUseBytes: UInt64, frequencyMHz: Double? = nil) {
        self.utilization = utilization; self.allocatedBytes = allocatedBytes
        self.inUseBytes = inUseBytes; self.frequencyMHz = frequencyMHz
    }
}

public struct PowerReading: Sendable, Codable, Equatable {
    public var cpuWatts: Double
    public var gpuWatts: Double
    public var aneWatts: Double
    public var dramWatts: Double
    public init(cpuWatts: Double, gpuWatts: Double, aneWatts: Double, dramWatts: Double) {
        self.cpuWatts = cpuWatts; self.gpuWatts = gpuWatts; self.aneWatts = aneWatts; self.dramWatts = dramWatts
    }
    public var total: Double { cpuWatts + gpuWatts + aneWatts + dramWatts }
}

public struct MemoryReading: Sendable, Codable, Equatable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var cachedBytes: UInt64
    public var swapUsedBytes: UInt64
    public var pressure: MemoryPressure
    public init(totalBytes: UInt64, usedBytes: UInt64, appBytes: UInt64, wiredBytes: UInt64,
                compressedBytes: UInt64, cachedBytes: UInt64, swapUsedBytes: UInt64, pressure: MemoryPressure) {
        self.totalBytes = totalBytes; self.usedBytes = usedBytes; self.appBytes = appBytes
        self.wiredBytes = wiredBytes; self.compressedBytes = compressedBytes
        self.cachedBytes = cachedBytes; self.swapUsedBytes = swapUsedBytes; self.pressure = pressure
    }
    public var usedFraction: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) }
}

public struct DiskReading: Sendable, Codable, Equatable {
    public var totalBytes: UInt64
    public var freeBytes: UInt64
    public var readBytesPerSec: Double
    public var writeBytesPerSec: Double
    public var smartCriticalWarning: Bool?
    public var wearPercent: Double?
    public var temperatureC: Double?
    public init(totalBytes: UInt64, freeBytes: UInt64, readBytesPerSec: Double, writeBytesPerSec: Double,
                smartCriticalWarning: Bool? = nil, wearPercent: Double? = nil, temperatureC: Double? = nil) {
        self.totalBytes = totalBytes; self.freeBytes = freeBytes
        self.readBytesPerSec = readBytesPerSec; self.writeBytesPerSec = writeBytesPerSec
        self.smartCriticalWarning = smartCriticalWarning; self.wearPercent = wearPercent; self.temperatureC = temperatureC
    }
    public var freeFraction: Double { totalBytes == 0 ? 1 : Double(freeBytes) / Double(totalBytes) }
    public var usedFraction: Double { 1 - freeFraction }
}

public struct BatteryReading: Sendable, Codable, Equatable {
    public var chargeFraction: Double
    public var isCharging: Bool
    public var onACPower: Bool
    public var cycleCount: Int
    public var maxCapacityFraction: Double?   // capacité max / capacité design
    public var temperatureC: Double?
    public var watts: Double?                 // >0 charge, <0 décharge
    public var adapterWatts: Double?
    public var timeRemainingMinutes: Int?
    public init(chargeFraction: Double, isCharging: Bool, onACPower: Bool, cycleCount: Int,
                maxCapacityFraction: Double? = nil, temperatureC: Double? = nil, watts: Double? = nil,
                adapterWatts: Double? = nil, timeRemainingMinutes: Int? = nil) {
        self.chargeFraction = chargeFraction; self.isCharging = isCharging; self.onACPower = onACPower
        self.cycleCount = cycleCount; self.maxCapacityFraction = maxCapacityFraction
        self.temperatureC = temperatureC; self.watts = watts; self.adapterWatts = adapterWatts
        self.timeRemainingMinutes = timeRemainingMinutes
    }
}

public struct NetworkReading: Sendable, Codable, Equatable {
    public var downBytesPerSec: Double
    public var upBytesPerSec: Double
    public var rssi: Int?
    public var noise: Int?
    public var linkRateMbps: Double?
    public var wifiConnected: Bool
    public init(downBytesPerSec: Double, upBytesPerSec: Double, rssi: Int? = nil, noise: Int? = nil,
                linkRateMbps: Double? = nil, wifiConnected: Bool = false) {
        self.downBytesPerSec = downBytesPerSec; self.upBytesPerSec = upBytesPerSec
        self.rssi = rssi; self.noise = noise; self.linkRateMbps = linkRateMbps; self.wifiConnected = wifiConnected
    }
}

public struct TemperatureReading: Sendable, Codable, Equatable {
    public var perfCoresC: Double?
    public var effCoresC: Double?
    public var gpuC: Double?
    public var socC: Double?
    public var batteryC: Double?
    public var ssdC: Double?
    public init(perfCoresC: Double? = nil, effCoresC: Double? = nil, gpuC: Double? = nil,
                socC: Double? = nil, batteryC: Double? = nil, ssdC: Double? = nil) {
        self.perfCoresC = perfCoresC; self.effCoresC = effCoresC; self.gpuC = gpuC
        self.socC = socC; self.batteryC = batteryC; self.ssdC = ssdC
    }
    /// Meilleure température connue pour la puce.
    public var chipC: Double? { socC ?? [perfCoresC, effCoresC, gpuC].compactMap { $0 }.max() }
}

public struct ProcessUsage: Sendable, Codable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    public var cpuPercent: Double       // en % d'un cœur (peut dépasser 100)
    public var memoryBytes: UInt64
    public var diskBytesPerSec: Double
    public var energyScore: Double
    public var id: Int32 { pid }
    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64,
                diskBytesPerSec: Double = 0, energyScore: Double = 0) {
        self.pid = pid; self.name = name; self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes; self.diskBytesPerSec = diskBytesPerSec; self.energyScore = energyScore
    }
}

/// Photographie immuable de l'état du Mac. Une valeur `nil` = donnée indisponible.
public struct Snapshot: Sendable, Codable, Equatable {
    public var date: Date
    public var cpu: CPUReading?
    public var gpu: GPUReading?
    public var power: PowerReading?
    public var memory: MemoryReading?
    public var disk: DiskReading?
    public var battery: BatteryReading?
    public var network: NetworkReading?
    public var temperatures: TemperatureReading?
    public var thermal: ThermalPressure
    public var topProcesses: [ProcessUsage]
    public var lowPowerMode: Bool
    public var foregroundApp: String?

    public init(date: Date = .now, cpu: CPUReading? = nil, gpu: GPUReading? = nil, power: PowerReading? = nil,
                memory: MemoryReading? = nil, disk: DiskReading? = nil, battery: BatteryReading? = nil,
                network: NetworkReading? = nil, temperatures: TemperatureReading? = nil,
                thermal: ThermalPressure = .nominal, topProcesses: [ProcessUsage] = [],
                lowPowerMode: Bool = false, foregroundApp: String? = nil) {
        self.date = date; self.cpu = cpu; self.gpu = gpu; self.power = power; self.memory = memory
        self.disk = disk; self.battery = battery; self.network = network; self.temperatures = temperatures
        self.thermal = thermal; self.topProcesses = topProcesses
        self.lowPowerMode = lowPowerMode; self.foregroundApp = foregroundApp
    }

    public static let empty = Snapshot()
}
