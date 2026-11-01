import Foundation
import SiliciumShared

/// Seuils configurables (réglages + calibrage du sprint 6).
public struct HealthThresholds: Sendable, Codable, Equatable {
    public var swapPenaltyBytes: UInt64 = 4 * 1024 * 1024 * 1024
    public var diskFreeWarn = 0.15, diskFreeBad = 0.10, diskFreeCritical = 0.05
    public var batteryMinCapacity = 0.80
    public var batteryChargeHotC = 40.0
    public var rssiWeak = -75
    public var sustainedProcessCPU = 90.0       // % d'un cœur
    public var sustainedSeconds = 300.0
    public var weights: [ComponentID: Double] = Dictionary(uniqueKeysWithValues: ComponentID.allCases.map { ($0, $0.defaultWeight) })
    public init() {}
}

/// Calcule les scores. Principe clé : charge ≠ problème — une charge élevée ne coûte des points
/// que si elle est soutenue, inattendue (arrière-plan) ou accompagnée de throttling.
public struct HealthEngine: Sendable {
    public var thresholds: HealthThresholds

    // État pour l'hystérésis et les conditions soutenues.
    private var shown: [ComponentID: HealthLevel] = [:]
    private var pending: [ComponentID: (level: HealthLevel, since: Date)] = [:]
    private var sustainedSince: [String: Date] = [:]

    public init(thresholds: HealthThresholds = .init()) { self.thresholds = thresholds }

    public static let hysteresisDown: TimeInterval = 10   // vers ambre/rouge
    public static let hysteresisUp: TimeInterval = 30     // retour au vert

    private mutating func sustained(_ key: String, _ cond: Bool, now: Date) -> TimeInterval {
        if cond {
            if sustainedSince[key] == nil { sustainedSince[key] = now }
            return now.timeIntervalSince(sustainedSince[key]!)
        }
        sustainedSince[key] = nil
        return 0
    }

    public mutating func evaluate(_ s: Snapshot, now: Date = .now) -> HealthReport {
        var items: [ComponentHealth] = []
        for id in ComponentID.allCases {
            let raw = rawHealth(id, s, now: now)
            items.append(applyHysteresis(raw, now: now))
        }

        let counted = items.filter { $0.level != .unavailable && (thresholds.weights[$0.component] ?? 0) > 0 }
        let wsum = counted.reduce(0) { $0 + (thresholds.weights[$1.component] ?? 0) }
        let avg = wsum > 0 ? counted.reduce(0) { $0 + $1.score * (thresholds.weights[$1.component] ?? 0) } / wsum : 100
        let worst = counted.map(\.score).min() ?? 100
        let g = max(0, min(avg, worst + 25))
        let level = HealthLevel(score: g)

        let summary: String
        if let bad = counted.filter({ $0.level != .ok }).min(by: { $0.score < $1.score }) {
            summary = level == .critical ? "Ton Mac a un problème — \(bad.component.title)" : "Ton Mac demande de l'attention — \(bad.component.title)"
        } else {
            summary = "Ton Mac va bien"
        }
        return HealthReport(date: s.date, globalScore: g, globalLevel: level, summary: summary, components: items)
    }

    private mutating func applyHysteresis(_ raw: ComponentHealth, now: Date) -> ComponentHealth {
        var out = raw
        let id = raw.component
        guard raw.level != .unavailable else { shown[id] = nil; pending[id] = nil; return out }
        guard let current = shown[id] else { shown[id] = raw.level; return out }
        if raw.level == current { pending[id] = nil; return out }
        if let p = pending[id], p.level == raw.level {
            let wait = raw.level == .ok ? Self.hysteresisUp : Self.hysteresisDown
            // Une aggravation (ok→rouge) passe après 10 s ; une amélioration vers le vert après 30 s.
            let needed = (raw.level > current && raw.level != .ok) ? Self.hysteresisDown : wait
            if now.timeIntervalSince(p.since) >= needed { shown[id] = raw.level; pending[id] = nil; return out }
        } else {
            pending[id] = (raw.level, now)
        }
        out.level = current
        return out
    }

    // MARK: - Règles par composante

    private func make(_ id: ComponentID, _ score: Double, _ reason: String, load: Double, headline: String) -> ComponentHealth {
        let s = max(0, min(100, score))
        return ComponentHealth(component: id, score: s, level: HealthLevel(score: s), reason: reason, load: clamp01(load), headline: headline)
    }

    private func unavailable(_ id: ComponentID, _ why: String = "Donnée indisponible") -> ComponentHealth {
        ComponentHealth(component: id, score: 100, level: .unavailable, reason: why, load: 0, headline: "—")
    }

    private mutating func rawHealth(_ id: ComponentID, _ s: Snapshot, now: Date) -> ComponentHealth {
        switch id {
        case .chip:
            var score = 100.0; var reasons: [String] = []
            switch s.thermal {
            case .nominal: break
            case .moderate: score -= 20; reasons.append("pression thermique modérée")
            case .heavy: score -= 50; reasons.append("pression thermique forte — la puce ralentit")
            case .critical: score -= 80; reasons.append("pression thermique critique")
            }
            let load = s.power.map { $0.total / 20 } ?? s.cpu?.overall ?? 0
            let head = s.temperatures?.chipC.map(Fmt.celsius) ?? s.power.map { Fmt.watts($0.total) } ?? s.thermal.label
            return make(.chip, score, reasons.first.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "Température et puissance normales.", load: load, headline: head)

        case .performanceCores:
            guard let cpu = s.cpu, !cpu.perfLoad.isEmpty else { return unavailable(id) }
            var score = 100.0; var reason = "Charge normale."
            // Processus d'arrière-plan qui monopolise un cœur pendant 5 min.
            let hog = s.topProcesses.first { $0.cpuPercent > thresholds.sustainedProcessCPU && $0.name != s.foregroundApp }
            let t = sustained("cpuHog", hog != nil, now: now)
            if let hog, t >= thresholds.sustainedSeconds {
                score -= 15; reason = "\(hog.name) occupe un cœur à plus de \(Int(thresholds.sustainedProcessCPU)) % en arrière-plan."
            }
            if s.thermal >= .heavy { score -= 15; reason = "Les cœurs sont bridés par la chaleur." }
            let head = cpu.perfFrequencyMHz.map(Fmt.ghz) ?? Fmt.percent(cpu.perfAverage)
            return make(id, score, reason, load: cpu.perfAverage, headline: "\(Fmt.percent(cpu.perfAverage)) · \(head)")

        case .efficiencyCores:
            guard let cpu = s.cpu, !cpu.effLoad.isEmpty else { return unavailable(id) }
            var score = 100.0; var reason = "Charge normale."
            let idle = s.cpu.map { $0.perfAverage < 0.1 } ?? false
            let t = sustained("effSat", cpu.effAverage > 0.9 && idle, now: now)
            if t >= thresholds.sustainedSeconds { score -= 15; reason = "Cœurs d'efficacité saturés alors que le Mac est au repos : un processus parasite est probable." }
            return make(id, score, reason, load: cpu.effAverage, headline: Fmt.percent(cpu.effAverage))

        case .gpu:
            guard let gpu = s.gpu else { return unavailable(id) }
            var score = 100.0; var reason = "Charge normale."
            let t = sustained("gpuHigh", gpu.utilization > 0.8, now: now)
            if t >= thresholds.sustainedSeconds { score -= 10; reason = "Charge GPU élevée depuis plus de 5 min." }
            if s.thermal >= .heavy && gpu.utilization > 0.5 { score -= 15; reason = "Le GPU est bridé par la chaleur." }
            return make(id, score, reason, load: gpu.utilization, headline: Fmt.percent(gpu.utilization))

        case .neuralEngine:
            guard let p = s.power else { return unavailable(id) }
            return make(id, 100, p.aneWatts > 0.05 ? "Neural Engine actif." : "Au repos.", load: p.aneWatts / 4, headline: Fmt.watts(p.aneWatts))

        case .memory:
            guard let m = s.memory else { return unavailable(id) }
            var score = 100.0; var reason = "Mémoire à l'aise."
            switch m.pressure {
            case .normal: break
            case .warning: score -= 25; reason = "Pression mémoire jaune : macOS compresse et déplace des données."
            case .critical: score -= 60; reason = "Pression mémoire rouge : le Mac manque de mémoire."
            }
            if m.swapUsedBytes > thresholds.swapPenaltyBytes {
                score -= 15; reason = "Le swap dépasse \(Fmt.bytes(thresholds.swapPenaltyBytes)) (\(Fmt.bytes(m.swapUsedBytes)) utilisés)."
            }
            return make(id, score, reason, load: m.usedFraction, headline: "\(Fmt.bytes(m.usedBytes)) / \(Fmt.bytes(m.totalBytes))")

        case .ssd:
            guard let d = s.disk, d.totalBytes > 0 else { return unavailable(id) }
            var score = 100.0; var reason = "Espace et santé corrects."
            if d.freeFraction < thresholds.diskFreeCritical { score -= 70; reason = "Disque presque plein : \(Fmt.bytes(d.freeBytes)) libres." }
            else if d.freeFraction < thresholds.diskFreeBad { score -= 40; reason = "Disque plein à plus de 90 % : \(Fmt.bytes(d.freeBytes)) libres." }
            else if d.freeFraction < thresholds.diskFreeWarn { score -= 20; reason = "Il reste moins de 15 % d'espace libre." }
            if d.smartCriticalWarning == true { score -= 100; reason = "Le SSD signale un avertissement critique SMART." }
            let io = d.readBytesPerSec + d.writeBytesPerSec
            return make(id, score, reason, load: min(1, io / 1_500_000_000) , headline: "\(Fmt.bytes(d.freeBytes)) libres")

        case .battery:
            guard let b = s.battery else { return unavailable(id, "Pas de batterie détectée") }
            var score = 100.0; var reason = "Batterie en bonne santé."
            if let cap = b.maxCapacityFraction, cap < thresholds.batteryMinCapacity {
                score -= 30; reason = "Capacité maximale à \(Fmt.percent(cap)) de l'origine : usure avancée."
            }
            if let t = b.temperatureC ?? s.temperatures?.batteryC, b.isCharging, t > thresholds.batteryChargeHotC {
                score -= 20; reason = "La batterie chauffe en charge (\(Fmt.celsius(t)))."
            }
            let draw = abs(b.watts ?? 0)
            return make(id, score, reason, load: draw / 30, headline: Fmt.percent(b.chargeFraction) + (b.isCharging ? " ⚡︎" : ""))

        case .wireless:
            guard let n = s.network else { return unavailable(id) }
            guard n.wifiConnected, let rssi = n.rssi else {
                return make(id, 100, "Wi-Fi non connecté.", load: 0, headline: "Hors ligne")
            }
            var score = 100.0; var reason = "Signal \(rssi) dBm."
            if rssi < thresholds.rssiWeak { score -= 20; reason = "Signal Wi-Fi faible (\(rssi) dBm)." }
            return make(id, score, reason, load: (n.downBytesPerSec + n.upBytesPerSec) / 12_500_000, headline: "\(rssi) dBm")

        case .power:
            guard let b = s.battery else { return unavailable(id) }
            var score = 100.0; var reason = b.onACPower ? "Secteur branché." : "Sur batterie."
            if b.onACPower, let w = b.watts, w < -2, !b.isCharging {
                score -= 30; reason = "La batterie se vide malgré le secteur : chargeur trop faible ?"
            }
            return make(id, score, reason, load: b.onACPower ? 0.3 : 0.1,
                        headline: b.adapterWatts.map { "\(Int($0)) W" } ?? (b.onACPower ? "Secteur" : "Batterie"))
        }
    }
}
