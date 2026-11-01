import SwiftUI
import SiliciumShared
import SiliciumCore
import SiliciumStorage

struct ScoreRing: View {
    let score: Double
    let level: HealthLevel
    var size: CGFloat = 64
    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: size * 0.12)
            Circle().trim(from: 0, to: level == .unavailable ? 0 : score / 100)
                .stroke(level.color.gradient, style: StrokeStyle(lineWidth: size * 0.12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(level == .unavailable ? "—" : "\(Int(score.rounded()))").font(.system(size: size * 0.34, weight: .bold, design: .rounded)).monospacedDigit()
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: score)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level == .unavailable ? "Mesure indisponible" : "Score \(Int(score.rounded())) sur 100, \(level.label)")
    }
}

enum DetailRange: String, CaseIterable, Identifiable {
    case live = "60 s", hour = "1 h", day = "24 h", week = "7 j"
    var id: String { rawValue }
    var history: HistoryRange? {
        switch self { case .live: nil; case .hour: .hour; case .day: .day; case .week: .week }
    }
}

/// Fiche détaillée d'une composante (F2).
struct DetailPanel: View {
    let model: AppModel
    let id: ComponentID
    @State private var range: DetailRange = .live

    var body: some View {
        let h = model.health(id)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { model.showOverview() } label: {
                    Label("Vue d’ensemble", systemImage: "chevron.left")
                }.buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
                header(h)
                Text(ComponentInfo.purpose(id)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if id == .chip || ComponentInfo.isInsideChip(id) { chipExplorer }
                if let tip = ComponentInfo.tip(id, level: h?.level ?? .ok) {
                    Label(tip, systemImage: "lightbulb.fill")
                        .font(.callout).foregroundStyle(.primary)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                factsGrid
                if ComponentInfo.facts(id, model.snapshot).isEmpty {
                    Label("Aucune mesure disponible pour ce composant pour le moment.", systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Picker("Période", selection: $range) { ForEach(DetailRange.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden()
                ForEach(ComponentInfo.charts(id)) { spec in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(spec.title).font(.subheadline.weight(.medium))
                            Spacer()
                            if let v = Metric.value(spec.metric, in: model.snapshot) {
                                Text(spec.format(v)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                        if let hr = range.history {
                            HistoryChart(repo: model.history, metric: spec.metric.rawValue, range: hr, color: spec.color, yDomain: nil, format: spec.format)
                        } else {
                            LiveChart(points: model.store.series(spec.metric, last: 60), color: spec.color, yDomain: spec.domain, format: spec.format)
                        }
                    }
                }
                if range != .live {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Score de santé").font(.subheadline.weight(.medium))
                        HistoryChart(repo: model.history, metric: "score." + id.rawValue, range: range.history!, color: Theme.ok, yDomain: 0...100, format: { "\(Int($0))" })
                    }
                }
                processes
                if id == .battery { Button("Rapport de santé de la batterie…") { model.showBatteryReport = true }.buttonStyle(.bordered) }
            }
            .padding(20)
        }
        .scrollIndicators(.never)
    }

    private var chipExplorer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if model.inspectChip {
                    model.select(.chip)
                    model.inspectChip = false
                } else { model.inspectChip = true }
            } label: {
                Label(model.inspectChip ? "Revenir à la puce" : "Explorer les cœurs", systemImage: model.inspectChip ? "cpu" : "square.3.layers.3d")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
            if model.inspectChip {
                Text("Les zones colorées représentent l’activité des unités de calcul. Leur disposition est schématique.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach([ComponentID.performanceCores, .efficiencyCores, .gpu, .neuralEngine]) { component in
                    Button { model.select(component) } label: {
                        HStack {
                            Label(ComponentInfo.shortTitle(component), systemImage: component.symbol)
                            Spacer()
                            Text(model.health(component)?.headline ?? "—").monospacedDigit()
                            Image(systemName: "chevron.right").font(.caption2)
                        }.font(.callout)
                    }.buttonStyle(.plain).padding(.vertical, 4)
                }
            }
        }
        .padding(12).background(Theme.accent.opacity(0.08), in: .rect(cornerRadius: 12))
    }

    @ViewBuilder private func header(_ h: ComponentHealth?) -> some View {
        HStack(spacing: 14) {
            ScoreRing(score: h?.score ?? 100, level: h?.level ?? .unavailable)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: id.symbol).foregroundStyle(h?.level.color ?? Theme.neutral)
                    Text(id.title).font(.title2.weight(.semibold))
                }
                StatusBadge(level: h?.level ?? .unavailable)
                Text(h?.reason ?? "Donnée indisponible").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var factsGrid: some View {
        let facts = ComponentInfo.facts(id, model.snapshot)
        return Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(facts) { f in
                GridRow {
                    Text(f.label).foregroundStyle(.secondary)
                    Text(f.value).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.callout)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private var processes: some View {
        let sort = ComponentInfo.processSort(id)
        if sort != .none {
            let procs = model.snapshot.topProcesses.sorted {
                switch sort {
                case .cpu: $0.cpuPercent > $1.cpuPercent
                case .memory: $0.memoryBytes > $1.memoryBytes
                case .disk: $0.diskBytesPerSec > $1.diskBytesPerSec
                case .none: false
                }
            }.prefix(5)
            VStack(alignment: .leading, spacing: 8) {
                Text("Processus les plus actifs").font(.subheadline.weight(.medium))
                ForEach(Array(procs)) { p in
                    HStack {
                        Text(p.name).lineLimit(1)
                        Spacer()
                        Text(value(p, sort)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func value(_ p: ProcessUsage, _ s: ComponentInfo.ProcessSort) -> String {
        switch s {
        case .cpu: "\(Int(p.cpuPercent)) %"
        case .memory: Fmt.bytes(p.memoryBytes)
        case .disk: Fmt.rate(p.diskBytesPerSec)
        case .none: ""
        }
    }
}

/// Vue d'ensemble quand rien n'est sélectionné.
struct OverviewPanel: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("L’essentiel").font(.title2.weight(.semibold))
                HStack(spacing: 16) {
                    ScoreRing(score: model.report.globalScore, level: model.report.globalLevel, size: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.report.summary).font(.title3.weight(.semibold))
                        StatusBadge(level: model.report.globalLevel)
                    }
                }
                let watch = model.report.watchlist()
                if !watch.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("À surveiller").font(.subheadline.weight(.medium))
                        ForEach(watch) { c in
                            Button { model.select(c.component) } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: c.level.symbol).foregroundStyle(c.level.color)
                                    VStack(alignment: .leading) { Text(c.component.title).font(.callout.weight(.medium)); Text(c.reason).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                }
                                .padding(10).background(c.level.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Composantes").font(.subheadline.weight(.medium)).padding(.bottom, 4)
                    ForEach(ComponentID.allCases) { id in
                        ComponentRow(model: model, id: id) { model.select(id) }
                    }
                }
                Button { model.showDiagnosis = true } label: { Label("Pourquoi mon Mac rame ?", systemImage: "stethoscope") }.buttonStyle(.borderedProminent)
                Text("Sélectionne un composant dans la liste ou directement sur le modèle. Ses mesures et son historique apparaîtront ici.").font(.caption).foregroundStyle(.secondary)
                Text("Représentation pédagogique du matériel Apple Silicon.").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .scrollIndicators(.never)
    }
}

struct ComponentRow: View {
    let model: AppModel
    let id: ComponentID
    var action: () -> Void
    var body: some View {
        let h = model.health(id)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: id.symbol).frame(width: 20).foregroundStyle(h?.level.color ?? Theme.neutral)
                Text(id.title).font(.callout)
                Spacer(minLength: 8)
                Text(h?.headline ?? "—").font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: h?.level.symbol ?? "questionmark.circle").foregroundStyle(h?.level.color ?? Theme.neutral).font(.caption)
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(id.title), \(h?.headline ?? "indisponible"), \(h?.level.label ?? "")")
    }
}
