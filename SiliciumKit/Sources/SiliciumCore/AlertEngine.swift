import Foundation
import SiliciumShared

public struct HealthAlert: Sendable, Equatable, Identifiable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case throttling, memoryPressure, diskFull, batteryHot, batteryWorn, weakWiFi, smart
    }
    public var kind: Kind
    public var component: ComponentID
    public var title: String
    public var body: String
    public var severity: HealthLevel
    public var date: Date
    public var id: String { "\(kind.rawValue)-\(Int(date.timeIntervalSince1970))" }
    public init(kind: Kind, component: ComponentID, title: String, body: String, severity: HealthLevel, date: Date) {
        self.kind = kind; self.component = component; self.title = title
        self.body = body; self.severity = severity; self.date = date
    }
}

/// Seuils → alertes. Anti-spam : une alerte par problème et par fenêtre de 30 min.
public struct AlertEngine: Sendable {
    public var cooldown: TimeInterval = 30 * 60
    public var enabled: Set<HealthAlert.Kind> = Set(HealthAlert.Kind.allCases)
    public var diskFullThreshold = 0.90
    public var throttleSeconds: TimeInterval = 120

    private var lastFired: [HealthAlert.Kind: Date] = [:]
    private var since: [HealthAlert.Kind: Date] = [:]

    public init() {}

    private mutating func held(_ k: HealthAlert.Kind, _ cond: Bool, now: Date) -> TimeInterval {
        if cond { if since[k] == nil { since[k] = now }; return now.timeIntervalSince(since[k]!) }
        since[k] = nil; return 0
    }

    private mutating func fire(_ a: HealthAlert, into out: inout [HealthAlert]) {
        guard enabled.contains(a.kind) else { return }
        if let last = lastFired[a.kind], a.date.timeIntervalSince(last) < cooldown { return }
        lastFired[a.kind] = a.date
        out.append(a)
    }

    public mutating func evaluate(_ s: Snapshot, now: Date = .now) -> [HealthAlert] {
        var out: [HealthAlert] = []

        if held(.throttling, s.thermal >= .heavy, now: now) >= throttleSeconds {
            fire(HealthAlert(kind: .throttling, component: .chip, title: "Le Mac est bridé par la chaleur",
                       body: "Pression thermique « \(s.thermal.label.lowercased()) » depuis plus de 2 minutes. Ferme les apps gourmandes ou laisse-le refroidir.",
                       severity: .critical, date: now), into: &out)
        }
        if let m = s.memory, held(.memoryPressure, m.pressure == .critical, now: now) >= 5 {
            fire(HealthAlert(kind: .memoryPressure, component: .memory, title: "Pression mémoire rouge",
                       body: "Le Mac manque de mémoire (\(Fmt.bytes(m.swapUsedBytes)) de swap). Ferme quelques apps.",
                       severity: .critical, date: now), into: &out)
        }
        if let d = s.disk, d.totalBytes > 0, d.usedFraction > diskFullThreshold {
            fire(HealthAlert(kind: .diskFull, component: .ssd, title: "Disque presque plein",
                       body: "Il reste \(Fmt.bytes(d.freeBytes)) (\(Fmt.percent(d.freeFraction))). Libère de l'espace.",
                       severity: .warning, date: now), into: &out)
        }
        if let d = s.disk, d.smartCriticalWarning == true {
            fire(HealthAlert(kind: .smart, component: .ssd, title: "Avertissement SMART du SSD",
                       body: "Le SSD signale un état critique. Sauvegarde tes données.",
                       severity: .critical, date: now), into: &out)
        }
        if let b = s.battery, let t = b.temperatureC ?? s.temperatures?.batteryC,
           held(.batteryHot, b.isCharging && t > 40, now: now) >= 60 {
            fire(HealthAlert(kind: .batteryHot, component: .battery, title: "La batterie chauffe en charge",
                       body: "Température à \(Fmt.celsius(t)). Évite de charger sur une surface qui retient la chaleur.",
                       severity: .warning, date: now), into: &out)
        }
        if let b = s.battery, let cap = b.maxCapacityFraction,
           held(.batteryWorn, cap < 0.8, now: now) >= 5 {
            fire(HealthAlert(kind: .batteryWorn, component: .battery, title: "Batterie usée",
                       body: "Capacité maximale à \(Fmt.percent(cap)). Un remplacement peut être utile.",
                       severity: .warning, date: now), into: &out)
        }
        if let n = s.network, n.wifiConnected, let r = n.rssi,
           held(.weakWiFi, r < -75, now: now) >= 60 {
            fire(HealthAlert(kind: .weakWiFi, component: .wireless, title: "Signal Wi-Fi faible",
                       body: "\(r) dBm depuis plus d'une minute. Rapproche-toi du routeur.",
                       severity: .warning, date: now), into: &out)
        }
        return out
    }
}
