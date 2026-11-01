import Foundation
import SiliciumShared
import SiliciumCore

/// B1 — « Pourquoi mon Mac rame ? » : croise charge, mémoire et thermique pour nommer la vraie cause.
public struct Diagnosis: Sendable, Equatable {
    public struct Cause: Sendable, Equatable, Identifiable {
        public var id: String
        public var component: ComponentID
        public var severity: Double          // 0…1, sert au tri
        public var title: String
        public var detail: String
        public var advice: String
    }
    public var causes: [Cause]
    public var verdict: String
}

public enum DiagnosisEngine {
    public static func diagnose(_ s: Snapshot, report: HealthReport) -> Diagnosis {
        var causes: [Diagnosis.Cause] = []

        if s.thermal >= .moderate {
            let sev = s.thermal == .moderate ? 0.5 : (s.thermal == .heavy ? 0.85 : 1.0)
            causes.append(.init(id: "thermal", component: .chip, severity: sev,
                title: "La puce est bridée par la chaleur",
                detail: "Pression thermique \(s.thermal.label.lowercased()). Sans ventilateur, le M5 réduit ses fréquences pour se protéger.",
                advice: "Ferme les apps qui chargent le CPU/GPU, retire la coque, éloigne le Mac du soleil ou d'une surface molle."))
        }
        if let m = s.memory, m.pressure != .normal || m.swapUsedBytes > 4 << 30 {
            let sev = m.pressure == .critical ? 0.95 : (m.pressure == .warning ? 0.7 : 0.55)
            let top = s.topProcesses.sorted { $0.memoryBytes > $1.memoryBytes }.first
            causes.append(.init(id: "memory", component: .memory, severity: sev,
                title: "La mémoire est saturée",
                detail: "Pression \(m.pressure.label.lowercased()), \(Fmt.bytes(m.swapUsedBytes)) de swap sur le SSD." + (top.map { " Plus gros consommateur : \($0.name) (\(Fmt.bytes($0.memoryBytes)))." } ?? ""),
                advice: "Quitte \(top?.name ?? "les apps lourdes") ou ferme des onglets/fenêtres inutiles."))
        }
        if let cpu = s.cpu, cpu.overall > 0.75 {
            let top = s.topProcesses.first
            let bg = top.map { $0.name != s.foregroundApp } ?? false
            causes.append(.init(id: "cpu", component: .performanceCores, severity: min(0.9, cpu.overall),
                title: bg ? "Un processus d'arrière-plan sature le CPU" : "Le CPU est très sollicité",
                detail: "Charge globale \(Fmt.percent(cpu.overall))." + (top.map { " \($0.name) utilise \(Int($0.cpuPercent)) % d'un cœur." } ?? ""),
                advice: bg ? "Quitte ou redémarre \(top!.name) depuis le Moniteur d'activité." : "C'est normal pendant une tâche lourde ; attends la fin ou ferme d'autres apps."))
        }
        if let gpu = s.gpu, gpu.utilization > 0.85 {
            causes.append(.init(id: "gpu", component: .gpu, severity: 0.6,
                title: "Le GPU est à plein régime",
                detail: "Utilisation \(Fmt.percent(gpu.utilization)).",
                advice: "Baisse la qualité graphique ou la résolution de l'app concernée."))
        }
        if let d = s.disk, d.freeFraction < 0.10 {
            causes.append(.init(id: "disk", component: .ssd, severity: d.freeFraction < 0.05 ? 0.9 : 0.65,
                title: "Le SSD est presque plein",
                detail: "Seulement \(Fmt.bytes(d.freeBytes)) libres : macOS manque d'espace pour le swap et les caches.",
                advice: "Libère de l'espace (Réglages Système › Stockage)."))
        }
        if let b = s.battery, !b.onACPower, b.chargeFraction < 0.2 || s.lowPowerMode {
            causes.append(.init(id: "battery", component: .battery, severity: 0.45,
                title: s.lowPowerMode ? "Le mode économie d'énergie limite les performances" : "Batterie faible",
                detail: "Charge \(Fmt.percent(b.chargeFraction))" + (s.lowPowerMode ? ", mode économie actif." : "."),
                advice: "Branche le chargeur pour retrouver toute la puissance."))
        }
        if let n = s.network, n.wifiConnected, let r = n.rssi, r < -75 {
            causes.append(.init(id: "wifi", component: .wireless, severity: 0.4,
                title: "Le Wi-Fi est faible", detail: "Signal \(r) dBm : les chargements paraîtront lents.",
                advice: "Rapproche-toi du routeur."))
        }
        causes.sort { $0.severity > $1.severity }
        let verdict = causes.first.map { "Cause probable : \($0.title.lowercased())." } ?? "Rien d'anormal : ton Mac a de la marge."
        return Diagnosis(causes: causes, verdict: verdict)
    }
}
