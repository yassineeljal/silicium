import SwiftUI
import Charts
#if canImport(FoundationModels)
import FoundationModels
#endif
import SiliciumShared
import SiliciumCore
import SiliciumStorage

// MARK: - B1 / B2 Diagnostic

struct DiagnosisView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var diagnosis: Diagnosis?
    @State private var explanation: String?
    @State private var explaining = false
    @State private var aiAvailable = false

    var body: some View {
        let d = diagnosis ?? model.diagnosis
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Pourquoi mon Mac rame ?", systemImage: "stethoscope").font(.title2.weight(.semibold))
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(d.verdict).font(.title3).foregroundStyle(d.causes.isEmpty ? Theme.ok : .primary)
            if d.causes.isEmpty {
                ContentUnavailableView("Tout est calme", systemImage: "checkmark.seal", description: Text("Aucune charge, pression mémoire ou chaleur anormale en ce moment."))
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(Array(d.causes.enumerated()), id: \.element.id) { i, c in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(i + 1)").font(.caption.weight(.bold)).frame(width: 22, height: 22)
                                        .background(Theme.warning.opacity(0.2), in: Circle())
                                    Image(systemName: c.component.symbol)
                                    Text(c.title).font(.headline)
                                    Spacer()
                                    Button("Voir") { model.select(c.component); dismiss() }.buttonStyle(.link)
                                }
                                Text(c.detail).foregroundStyle(.secondary)
                                Label(c.advice, systemImage: "wand.and.stars").font(.callout)
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            if aiAvailable {
                Divider()
                HStack {
                    Button { Task { await explain(d) } } label: { Label(explaining ? "Réflexion…" : "Expliquer simplement (IA locale)", systemImage: "sparkles") }
                        .disabled(explaining)
                    Text("Traité sur ton Mac, hors ligne.").font(.caption).foregroundStyle(.secondary)
                }
                if let explanation { Text(explanation).textSelection(.enabled).padding(12).background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10)) }
            }
        }
        .padding(24).frame(width: 560, height: 520)
        .task {
            diagnosis = model.diagnosis
            #if canImport(FoundationModels)
            if case .available = SystemLanguageModel.default.availability { aiAvailable = true }
            #endif
        }
    }

    private func explain(_ d: Diagnosis) async {
        #if canImport(FoundationModels)
        explaining = true; defer { explaining = false }
        let facts = d.causes.map { "- \($0.title) : \($0.detail)" }.joined(separator: "\n")
        let prompt = "Voici des mesures de mon Mac :\n\(facts.isEmpty ? "- rien d'anormal" : facts)\nExplique en 3 phrases maximum, en français simple, pourquoi il peut ramer et quoi faire."
        do {
            let session = LanguageModelSession(instructions: "Tu es un technicien Mac bienveillant. Tu réponds en français, de façon courte et concrète, sans jargon.")
            explanation = try await session.respond(to: prompt).content
        } catch {
            explanation = "L'IA locale n'a pas pu répondre (\(error.localizedDescription))."
        }
        #endif
    }
}

// MARK: - B3 Rapport de santé de la batterie

struct BatteryReportView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var points: [HistoryPoint] = []
    @State private var loaded = false

    private var trend: (perDay: Double, daysTo80: Double?)? {
        guard points.count >= 4, let first = points.first, let last = points.last else { return nil }
        let span = last.date.timeIntervalSince(first.date) / 86400
        guard span >= 2 else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first.date) / 86400 }, ys = points.map(\.average)
        let n = Double(xs.count), mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let denom = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard denom > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / denom
        let current = last.average
        let days: Double? = slope < -0.00005 && current > 0.8 ? (current - 0.8) / -slope : nil
        return (slope, days)
    }

    var body: some View {
        let b = model.snapshot.battery
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Santé de la batterie", systemImage: "battery.100percent.bolt").font(.title2.weight(.semibold))
                Spacer()
                Button("Fermer") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let b {
                HStack(spacing: 28) {
                    stat("Capacité max.", b.maxCapacityFraction.map { Fmt.percent($0) } ?? "—", (b.maxCapacityFraction ?? 1) < 0.8 ? Theme.warning : Theme.ok)
                    stat("Cycles", "\(b.cycleCount)", .primary)
                    stat("Température", b.temperatureC.map(Fmt.celsius) ?? "—", .primary)
                    stat("Charge", Fmt.percent(b.chargeFraction), .primary)
                }
            }
            Text("Tendance de la capacité (7 jours)").font(.headline)
            if points.isEmpty {
                ContentUnavailableView(loaded ? "Pas encore de données" : "Chargement…", systemImage: "chart.line.downtrend.xyaxis",
                                       description: Text("Silicium enregistre la capacité maximale au fil des jours."))
                    .frame(height: 180)
            } else {
                Chart(points) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Capacité", p.average)).foregroundStyle(Theme.ok).interpolationMethod(.monotone)
                    RuleMark(y: .value("Seuil", 0.8)).foregroundStyle(Theme.warning.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYScale(domain: 0.7...1.05)
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) { v in AxisGridLine(); AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.percent(d)) } } } }
                .frame(height: 180)
            }
            Group {
                if let t = trend {
                    if let d = t.daysTo80 { Label("Au rythme actuel, la capacité passera sous 80 % dans environ \(Int(d)) jours (~\(Int(d / 30)) mois).", systemImage: "calendar.badge.clock") }
                    else { Label("La capacité est stable : aucun remplacement à prévoir.", systemImage: "checkmark.seal") }
                } else {
                    Label("Il faut au moins 2 jours de données pour estimer une tendance.", systemImage: "hourglass")
                }
            }.font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(24).frame(width: 560, height: 520)
        .task {
            points = (try? await model.history?.series(metric: Metric.batteryHealth.rawValue, range: .week)) ?? []
            loaded = true
        }
    }

    private func stat(_ t: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading) { Text(t).font(.caption).foregroundStyle(.secondary); Text(v).font(.title2.weight(.semibold).monospacedDigit()).foregroundStyle(c) }
    }
}

// MARK: - Premier lancement

struct OnboardingView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "cpu").font(.system(size: 54, weight: .light)).foregroundStyle(Theme.accent.gradient)
            VStack(spacing: 6) {
                Text("Bienvenue dans Silicium").font(.largeTitle.weight(.semibold))
                Text("L'intérieur de ton Mac, en 3D et en direct.").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 14) {
                row("cursorarrow.click", "Explore le matériel", "Clique un repère sur le modèle ou un composant dans la liste pour voir ses mesures.")
                row("square.3.layers.3d", "Comprends la puce", "Ouvre « Explorer les cœurs » pour découvrir les unités de calcul et leur activité.")
                row("menubar.rectangle", "Score dans la barre des menus", "Un clic pour savoir si ton Mac va bien.")
                row("bell.badge", "Alertes utiles", "Chaleur, mémoire saturée, disque plein : tu es prévenu, sans spam.")
                row("lock.shield", "100 % local", "Aucun compte, aucune donnée envoyée. Silicium lit les capteurs et ne modifie rien.")
            }
            Button("Commencer") { model.settings.hasOnboarded = true; dismiss() }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(36).frame(width: 520)
        .interactiveDismissDisabled()
    }
    private func row(_ s: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: s).font(.title2).frame(width: 34).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) { Text(t).font(.headline); Text(d).foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Réglages

public struct SettingsView: View {
    let model: AppModel
    public init(model: AppModel) { self.model = model }

    public var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("Général", systemImage: "gearshape") }
            AlertSettings(model: model).tabItem { Label("Alertes", systemImage: "bell") }
            DisplaySettings(model: model).tabItem { Label("Affichage 3D", systemImage: "cube") }
            DataSettings(model: model).tabItem { Label("Données", systemImage: "internaldrive") }
            AboutView().tabItem { Label("À propos", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

private struct GeneralSettings: View {
    @Bindable var settings: AppSettings
    init(model: AppModel) { settings = model.settings }
    var body: some View {
        Form {
            Picker("Icône de la barre des menus", selection: $settings.menuBarStyle) {
                ForEach(MenuBarStyle.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("Ouvrir Silicium à la connexion", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            Text("En arrière-plan, Silicium mesure toutes les 5 s sur secteur, 15 s sur batterie et 30 s en mode économie d'énergie. Fenêtre ou panneau ouverts : 1 s.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}

private struct AlertSettings: View {
    let model: AppModel
    @Bindable var settings: AppSettings
    init(model: AppModel) { self.model = model; settings = model.settings }
    var body: some View {
        Form {
            Toggle("Notifications d'alerte", isOn: $settings.alertsEnabled)
            Section("Seuils") {
                LabeledContent("Disque plein à partir de \(Int(settings.diskAlertThreshold * 100)) %") {
                    Slider(value: $settings.diskAlertThreshold, in: 0.7...0.98, step: 0.01).frame(width: 180)
                }
                LabeledContent("Batterie chaude en charge au-dessus de \(Int(settings.batteryHotThreshold)) °C") {
                    Slider(value: $settings.batteryHotThreshold, in: 35...50, step: 1).frame(width: 180)
                }
            }
            Section("Types d'alerte (une alerte par problème toutes les 30 min)") {
                ForEach(HealthAlert.Kind.allCases, id: \.self) { k in
                    Toggle(Self.name(k), isOn: Binding(
                        get: { !settings.disabledAlertKinds.contains(k.rawValue) },
                        set: { on in if on { settings.disabledAlertKinds.remove(k.rawValue) } else { settings.disabledAlertKinds.insert(k.rawValue) } }))
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.diskAlertThreshold) { model.applySettings() }
        .onChange(of: settings.batteryHotThreshold) { model.applySettings() }
        .onChange(of: settings.disabledAlertKinds) { model.applySettings() }
    }
    static func name(_ k: HealthAlert.Kind) -> String {
        switch k {
        case .throttling: "Throttling thermique (2 min)"
        case .memoryPressure: "Pression mémoire rouge"
        case .diskFull: "Disque presque plein"
        case .batteryHot: "Batterie chaude en charge"
        case .batteryWorn: "Batterie usée"
        case .weakWiFi: "Signal Wi-Fi faible"
        case .smart: "Avertissement SMART du SSD"
        }
    }
}

private struct DisplaySettings: View {
    @Bindable var settings: AppSettings
    init(model: AppModel) { settings = model.settings }
    var body: some View {
        Form {
            Toggle("Particules de flux (mémoire, batterie, réseau)", isOn: $settings.particlesEnabled)
            Toggle("Halo lumineux (bloom)", isOn: $settings.bloomEnabled)
            Text("Si « Réduire les animations » est activé dans Réglages Système, pulsations et particules sont désactivées automatiquement.")
                .font(.caption).foregroundStyle(.secondary)
        }.formStyle(.grouped)
    }
}

private struct DataSettings: View {
    let model: AppModel
    @State private var size: Int64 = 0
    var body: some View {
        Form {
            LabeledContent("Taille de l'historique", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
            Text("Agrégation 1 min / 15 min, conservé 30 jours, stocké localement dans ~/Library/Application Support/Silicium.").font(.caption).foregroundStyle(.secondary)
            Button("Afficher dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: AppModel.defaultHistoryPath)]) }
        }
        .formStyle(.grouped)
        .task { size = await model.history?.fileSize() ?? 0 }
    }
}

public struct AboutView: View {
    public init() {}
    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cpu").font(.system(size: 48, weight: .light)).foregroundStyle(Theme.accent.gradient)
            Text("Silicium").font(.title.weight(.semibold))
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")").foregroundStyle(.secondary)
            Text("Le moniteur 3D de ton Mac Apple Silicon.").multilineTextAlignment(.center)
            Text("Silicium lit les capteurs du Mac (IOKit, IOReport, SMC) et ne modifie rien. Aucune donnée ne quitte ton ordinateur.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
        }.padding()
    }
}
