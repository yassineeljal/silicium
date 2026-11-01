import SwiftUI
import SiliciumShared
import SiliciumCore

struct ChartSpec: Identifiable {
    let id: String
    let title: String
    let metric: Metric
    let color: Color
    var domain: ClosedRange<Double>?
    var format: (Double) -> String
}

struct Fact: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

/// Valeurs, graphiques et conseils propres à chaque composante.
enum ComponentInfo {
    static func isInsideChip(_ id: ComponentID) -> Bool {
        [.performanceCores, .efficiencyCores, .gpu, .neuralEngine].contains(id)
    }

    static func shortTitle(_ id: ComponentID) -> String {
        switch id {
        case .chip: "Puce"
        case .performanceCores: "Performance"
        case .efficiencyCores: "Efficacité"
        case .gpu: "Graphismes"
        case .neuralEngine: "Neural Engine"
        case .memory: "Mémoire"
        case .ssd: "Stockage"
        case .battery: "Batterie"
        case .wireless: "Réseau"
        case .power: "Alimentation"
        }
    }

    static func purpose(_ id: ComponentID) -> String {
        switch id {
        case .chip: "Le centre de calcul du Mac. Retrouve ici sa consommation et sa température."
        case .performanceCores: "Ces cœurs exécutent les tâches exigeantes : calculs, compilation et traitements lourds."
        case .efficiencyCores: "Ces cœurs s’occupent des tâches légères en économisant l’énergie."
        case .gpu: "La partie de la puce qui dessine l’écran et accélère les traitements graphiques."
        case .neuralEngine: "La partie de la puce spécialisée dans certains calculs d’intelligence artificielle."
        case .memory: "L’espace de travail partagé par tes applications. Une mémoire sous pression peut ralentir le Mac."
        case .ssd: "L’espace où sont conservés tes fichiers et tes applications. Vérifie ici l’espace libre et les transferts."
        case .battery: "La réserve d’énergie du Mac. Consulte sa charge, son usure et son autonomie."
        case .wireless: "Les échanges réseau du Mac : vitesse de transfert et signal Wi-Fi lorsqu’il est disponible."
        case .power: "La source d’énergie du Mac : batterie ou chargeur, et la puissance reçue."
        }
    }

    static func charts(_ id: ComponentID) -> [ChartSpec] {
        let pct: (Double) -> String = { Fmt.percent($0) }
        let watts: (Double) -> String = { Fmt.watts($0) }
        switch id {
        case .chip:
            return [ChartSpec(id: "p", title: "Puissance totale", metric: .powerTotal, color: Theme.accent, format: watts),
                    ChartSpec(id: "t", title: "Température", metric: .tempChip, color: Theme.warning, domain: 20...110, format: { Fmt.celsius($0) })]
        case .performanceCores: return [ChartSpec(id: "c", title: "Charge moyenne", metric: .cpuPerf, color: Theme.accent, domain: 0...1, format: pct),
                                        ChartSpec(id: "w", title: "Puissance CPU", metric: .powerCPU, color: Theme.warning, format: watts)]
        case .efficiencyCores: return [ChartSpec(id: "c", title: "Charge moyenne", metric: .cpuEff, color: Theme.ok, domain: 0...1, format: pct)]
        case .gpu: return [ChartSpec(id: "g", title: "Utilisation", metric: .gpu, color: Theme.accent, domain: 0...1, format: pct),
                           ChartSpec(id: "w", title: "Puissance GPU", metric: .powerGPU, color: Theme.warning, format: watts)]
        case .neuralEngine: return [ChartSpec(id: "a", title: "Puissance", metric: .powerANE, color: Theme.accent, format: watts)]
        case .memory: return [ChartSpec(id: "m", title: "Mémoire utilisée", metric: .memoryUsed, color: Theme.accent, domain: 0...1, format: pct),
                              ChartSpec(id: "s", title: "Swap", metric: .swap, color: Theme.warning, format: { Fmt.bytes($0) })]
        case .ssd: return [ChartSpec(id: "r", title: "Lecture", metric: .diskRead, color: Theme.accent, format: { Fmt.rate($0) }),
                           ChartSpec(id: "w", title: "Écriture", metric: .diskWrite, color: Theme.warning, format: { Fmt.rate($0) })]
        case .battery: return [ChartSpec(id: "c", title: "Charge", metric: .batteryCharge, color: Theme.ok, domain: 0...1, format: pct),
                               ChartSpec(id: "w", title: "Puissance (+ charge / − décharge)", metric: .batteryWatts, color: Theme.warning, domain: nil, format: watts)]
        case .wireless: return [ChartSpec(id: "d", title: "Débit descendant", metric: .netDown, color: Theme.accent, format: { Fmt.rate($0) }),
                                ChartSpec(id: "u", title: "Débit montant", metric: .netUp, color: Theme.warning, format: { Fmt.rate($0) })]
        case .power: return [ChartSpec(id: "w", title: "Puissance batterie", metric: .batteryWatts, color: Theme.accent, format: watts)]
        }
    }

    static func facts(_ id: ComponentID, _ s: Snapshot) -> [Fact] {
        switch id {
        case .chip:
            var f: [Fact] = [Fact(label: "Pression thermique", value: s.thermal.label)]
            if let p = s.power { f += [Fact(label: "Puissance totale", value: Fmt.watts(p.total)), Fact(label: "CPU", value: Fmt.watts(p.cpuWatts)), Fact(label: "GPU", value: Fmt.watts(p.gpuWatts)), Fact(label: "DRAM", value: Fmt.watts(p.dramWatts))] }
            if let t = s.temperatures?.chipC { f.append(Fact(label: "Température", value: Fmt.celsius(t))) }
            if s.lowPowerMode { f.append(Fact(label: "Mode économie", value: "Actif")) }
            return f
        case .performanceCores:
            guard let c = s.cpu else { return [] }
            var f = [Fact(label: "Charge moyenne", value: Fmt.percent(c.perfAverage))]
            if let hz = c.perfFrequencyMHz { f.append(Fact(label: "Fréquence", value: Fmt.ghz(hz))) }
            if let t = s.temperatures?.perfCoresC { f.append(Fact(label: "Température", value: Fmt.celsius(t))) }
            for (i, l) in c.perfLoad.enumerated() { f.append(Fact(label: "Cœur \(i + 1)", value: Fmt.percent(l))) }
            return f
        case .efficiencyCores:
            guard let c = s.cpu else { return [] }
            var f = [Fact(label: "Charge moyenne", value: Fmt.percent(c.effAverage))]
            if let hz = c.effFrequencyMHz { f.append(Fact(label: "Fréquence", value: Fmt.ghz(hz))) }
            if let t = s.temperatures?.effCoresC { f.append(Fact(label: "Température", value: Fmt.celsius(t))) }
            for (i, l) in c.effLoad.enumerated() { f.append(Fact(label: "Cœur \(i + 1)", value: Fmt.percent(l))) }
            return f
        case .gpu:
            guard let g = s.gpu else { return [] }
            var f = [Fact(label: "Utilisation", value: Fmt.percent(g.utilization)),
                     Fact(label: "Mémoire allouée", value: Fmt.bytes(g.allocatedBytes)), Fact(label: "Mémoire utilisée", value: Fmt.bytes(g.inUseBytes))]
            if let hz = g.frequencyMHz { f.append(Fact(label: "Fréquence", value: Fmt.ghz(hz))) }
            if let p = s.power { f.append(Fact(label: "Puissance", value: Fmt.watts(p.gpuWatts))) }
            if let t = s.temperatures?.gpuC { f.append(Fact(label: "Température", value: Fmt.celsius(t))) }
            return f
        case .neuralEngine:
            guard let p = s.power else { return [] }
            return [Fact(label: "Puissance", value: Fmt.watts(p.aneWatts)), Fact(label: "État", value: p.aneWatts > 0.05 ? "Actif" : "Inactif")]
        case .memory:
            guard let m = s.memory else { return [] }
            return [Fact(label: "Utilisée", value: "\(Fmt.bytes(m.usedBytes)) sur \(Fmt.bytes(m.totalBytes))"),
                    Fact(label: "Apps", value: Fmt.bytes(m.appBytes)), Fact(label: "Système (câblée)", value: Fmt.bytes(m.wiredBytes)),
                    Fact(label: "Compressée", value: Fmt.bytes(m.compressedBytes)), Fact(label: "En cache", value: Fmt.bytes(m.cachedBytes)),
                    Fact(label: "Swap", value: Fmt.bytes(m.swapUsedBytes)), Fact(label: "Pression", value: m.pressure.label)]
        case .ssd:
            guard let d = s.disk else { return [] }
            var f = [Fact(label: "Libre", value: "\(Fmt.bytes(d.freeBytes)) (\(Fmt.percent(d.freeFraction)))"), Fact(label: "Capacité", value: Fmt.bytes(d.totalBytes)),
                     Fact(label: "Lecture", value: Fmt.rate(d.readBytesPerSec)), Fact(label: "Écriture", value: Fmt.rate(d.writeBytesPerSec))]
            if let t = d.temperatureC ?? s.temperatures?.ssdC { f.append(Fact(label: "Température", value: Fmt.celsius(t))) }
            if let w = d.wearPercent { f.append(Fact(label: "Usure", value: "\(Int(w)) %")) }
            if let c = d.smartCriticalWarning { f.append(Fact(label: "SMART", value: c ? "Avertissement" : "OK")) }
            return f
        case .battery:
            guard let b = s.battery else { return [] }
            var f = [Fact(label: "Charge", value: Fmt.percent(b.chargeFraction)), Fact(label: "État", value: b.isCharging ? "En charge" : (b.onACPower ? "Sur secteur" : "Sur batterie")),
                     Fact(label: "Cycles", value: "\(b.cycleCount)")]
            if let c = b.maxCapacityFraction { f.append(Fact(label: "Capacité max.", value: Fmt.percent(c))) }
            if let t = b.temperatureC { f.append(Fact(label: "Température", value: Fmt.celsius(t))) }
            if let w = b.watts { f.append(Fact(label: "Puissance", value: Fmt.watts(w))) }
            if let m = b.timeRemainingMinutes { f.append(Fact(label: "Autonomie estimée", value: "\(m / 60) h \(m % 60) min")) }
            return f
        case .wireless:
            guard let n = s.network else { return [] }
            var f = [Fact(label: "Descendant", value: Fmt.rate(n.downBytesPerSec)), Fact(label: "Montant", value: Fmt.rate(n.upBytesPerSec))]
            if n.wifiConnected, let r = n.rssi { f += [Fact(label: "Signal", value: "\(r) dBm")] }
            if let nz = n.noise { f.append(Fact(label: "Bruit", value: "\(nz) dBm")) }
            if let l = n.linkRateMbps { f.append(Fact(label: "Débit de liaison", value: "\(Int(l)) Mb/s")) }
            return f
        case .power:
            guard let b = s.battery else { return [] }
            var f = [Fact(label: "Source", value: b.onACPower ? "Secteur" : "Batterie")]
            if let a = b.adapterWatts { f.append(Fact(label: "Chargeur", value: "\(Int(a)) W")) }
            if let w = b.watts { f.append(Fact(label: "Flux batterie", value: Fmt.watts(w))) }
            return f
        }
    }

    enum ProcessSort { case cpu, memory, disk, none }
    static func processSort(_ id: ComponentID) -> ProcessSort {
        switch id {
        case .chip, .performanceCores, .efficiencyCores, .gpu, .neuralEngine, .battery, .power: .cpu
        case .memory: .memory
        case .ssd: .disk
        case .wireless: .none
        }
    }

    static func tip(_ id: ComponentID, level: HealthLevel) -> String? {
        guard level == .warning || level == .critical else { return nil }
        switch id {
        case .chip: return "Laisse le Mac refroidir et ferme les apps gourmandes. Le M5 Air n'a pas de ventilateur : il ralentit pour se protéger."
        case .performanceCores, .efficiencyCores: return "Repère le processus fautif dans la liste ci-dessous, puis quitte-le depuis le Moniteur d'activité."
        case .gpu: return "Réduis la qualité graphique ou ferme l'app qui sollicite le GPU."
        case .memory: return "Ferme les apps ou onglets inutiles ; un redémarrage libère aussi la mémoire."
        case .ssd: return "Libère de l'espace : Réglages Système › Général › Stockage."
        case .battery: return "Évite la chaleur et les charges à 100 % prolongées ; envisage un remplacement si la capacité est basse."
        case .wireless: return "Rapproche-toi du routeur ou passe sur la bande 5 GHz."
        case .power: return "Utilise un chargeur d'au moins 35 W."
        case .neuralEngine: return nil
        }
    }
}
