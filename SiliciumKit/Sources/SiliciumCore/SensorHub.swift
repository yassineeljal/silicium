import Foundation
import SiliciumShared
import SiliciumSensors

public enum SamplingMode: Sendable, Equatable {
    case interactive        // fenêtre 3D ou panneau ouvert
    case backgroundAC       // arrière-plan, sur secteur
    case backgroundBattery  // arrière-plan, sur batterie
    case lowPower           // mode économie d'énergie

    /// Intervalle de base d'un tick (secondes).
    public var tick: Double {
        switch self {
        case .interactive: 1
        case .backgroundAC: 5
        case .backgroundBattery: 15
        case .lowPower: 30
        }
    }
    /// Multiple du tick pour les données « lentes » (mémoire, réseau, disque, processus…).
    var slowEvery: Int { self == .interactive ? 2 : 1 }
}

/// Planifie les lectures des samplers et diffuse des `Snapshot` immuables par `AsyncStream`.
public actor SensorHub {
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let network = NetworkSampler()
    private let disk = DiskSampler()
    private let battery = BatterySampler()
    private let gpu = GPUSampler()
    private let thermal = ThermalSampler()
    private let power = PowerSampler()
    private let temps = TemperatureSampler()
    private let processes = ProcessSampler()

    private var mode: SamplingMode = .backgroundAC
    private var task: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<Snapshot>.Continuation] = [:]
    private var tickCount = 0
    private var foregroundApp: String?
    public private(set) var latest = Snapshot.empty

    // Dernières valeurs lentes conservées entre deux ticks.
    private var cache = Snapshot.empty
    private var powerOut = PowerSampler.Output()

    public init() {}

    public func updates() -> AsyncStream<Snapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { c in
            continuations[id] = c
            c.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
            if latest.date != Snapshot.empty.date { c.yield(latest) }
        }
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }

    public func setMode(_ new: SamplingMode) {
        guard new != mode else { return }
        mode = new
        if task != nil { restart() }
    }

    public func setForegroundApp(_ name: String?) { foregroundApp = name }

    public func start() {
        guard task == nil else { return }
        restart()
    }

    public func stop() { task?.cancel(); task = nil }

    private func restart() {
        task?.cancel()
        let interval = mode.tick
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Une lecture complète. Exposé pour les tests et le mode « rafraîchir maintenant ».
    @discardableResult
    public func tick() -> Snapshot {
        tickCount += 1
        let slowDue = tickCount % mode.slowEvery == 0 || tickCount == 1

        var s = cache
        s.date = .now
        s.cpu = try? cpu.sample()
        s.gpu = (try? gpu.sample()) ?? nil
        if let p = try? power.sample() { powerOut = p }
        s.power = powerOut.power
        s.thermal = (try? thermal.sample()) ?? .nominal
        s.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        s.foregroundApp = foregroundApp

        if slowDue {
            s.memory = try? memory.sample()
            s.disk = try? disk.sample()
            s.battery = (try? battery.sample()) ?? nil
            s.network = try? network.sample()
            s.temperatures = (try? temps.sample()) ?? nil
            if let top = try? processes.sample() { s.topProcesses = top }
        }
        // Fréquences IOReport recollées sur les lectures CPU/GPU.
        s.cpu?.perfFrequencyMHz = powerOut.perfFreqMHz
        s.cpu?.effFrequencyMHz = powerOut.effFreqMHz
        s.gpu?.frequencyMHz = powerOut.gpuFreqMHz
        // Température SSD/batterie de repli depuis SMART et AppleSmartBattery.
        if s.temperatures?.ssdC == nil, let t = s.disk?.temperatureC {
            s.temperatures = (s.temperatures ?? TemperatureReading()); s.temperatures?.ssdC = t
        }
        if s.temperatures?.batteryC == nil, let t = s.battery?.temperatureC {
            s.temperatures = (s.temperatures ?? TemperatureReading()); s.temperatures?.batteryC = t
        }

        cache = s
        latest = s
        for c in continuations.values { c.yield(s) }
        return s
    }

    /// Diagnostic des sources disponibles (écran de debug).
    public func availability() -> [String: Bool] {
        ["IOReport (puissance)": power.isAvailable, "SMC (températures)": temps.isAvailable,
         "GPU (AGX)": latest.gpu != nil, "Batterie": latest.battery != nil, "Wi-Fi": latest.network?.wifiConnected ?? false]
    }
}
