import SwiftUI
import SiliciumShared
import SiliciumCore
import SiliciumStorage

/// Carte flottante au survol : nom, valeur clé, score, une phrase d'état.
struct HoverCard: View {
    let id: ComponentID
    let health: ComponentHealth?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: id.symbol).foregroundStyle(health?.level.color ?? Theme.neutral)
                Text(id.title).font(.headline)
                Spacer(minLength: 6)
                if let h = health, h.level != .unavailable { Text("\(Int(h.score))").font(.headline.monospacedDigit()).foregroundStyle(h.level.color) }
            }
            Text(health?.headline ?? "—").font(.title3.weight(.semibold).monospacedDigit())
            Text(health?.reason ?? "Donnée indisponible").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            StatusBadge(level: health?.level ?? .unavailable)
        }
        .padding(12).frame(width: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder((health?.level.color ?? Theme.neutral).opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .allowsHitTesting(false)
    }
}

struct AlertTimeline: View {
    let model: AppModel
    var body: some View {
        HStack(spacing: 10) {
            Label("Alertes récentes", systemImage: "bell").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if model.recentAlerts.isEmpty {
                Label("Aucune alerte — tout va bien", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.recentAlerts) { a in
                            let level = HealthLevel(rawValue: a.severity) ?? .warning
                            Button { if let c = ComponentID(rawValue: a.component) { model.select(c) } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: level.symbol).foregroundStyle(level.color)
                                    Text(a.title).lineLimit(1)
                                    Text(a.date, style: .time).foregroundStyle(.secondary)
                                }
                                .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(level.color.opacity(0.12), in: Capsule())
                            }.buttonStyle(.plain).help(a.body)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
    }
}

/// Fenêtre principale : scène 3D à gauche (≈ 70 %), panneau de détail à droite, alertes en bas.
public struct MainWindow: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ExplorerSidebar(model: model).frame(width: 180)
                Divider()
                ZStack(alignment: .topLeading) {
                    SceneContainer(model: model)
                        .accessibilityLabel("Vue 3D du matériel")
                        .accessibilityHint("La liste des composants permet de consulter les mêmes mesures au clavier.")
                        .overlay {
                            if let image = model.reviewSceneImage {
                                Image(nsImage: image).resizable().allowsHitTesting(false)
                            }
                        }
                    ComponentMarkers(model: model)
                    GeometryReader { geo in
                        if let id = model.hovered, model.selection != id {
                            HoverCard(id: id, health: model.health(id))
                                .position(cardPosition(in: geo.size))
                                .transition(.opacity)
                        }
                    }
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.12), value: model.hovered)
                    overlayHUD
                }
                .preferredColorScheme(.dark)
                .frame(minWidth: 520)
                Divider()
                Group {
                    if let sel = model.selection { DetailPanel(model: model, id: sel).id(sel) } else { OverviewPanel(model: model) }
                }
                .frame(width: 340)
                .background(.background)
            }
            Divider()
            AlertTimeline(model: model)
        }
        .frame(minWidth: 1080, minHeight: 700)
        .background(WindowVisibilityReader { model.windowOpen = $0 })
        .toolbar { toolbar }
        .sheet(isPresented: Binding(get: { model.showDiagnosis }, set: { model.showDiagnosis = $0 })) { DiagnosisView(model: model) }
        .sheet(isPresented: Binding(get: { model.showBatteryReport }, set: { model.showBatteryReport = $0 })) { BatteryReportView(model: model) }
        .sheet(isPresented: Binding(get: { !model.settings.hasOnboarded }, set: { if !$0 { model.settings.hasOnboarded = true } })) { OnboardingView(model: model) }
        .onAppear { model.windowOpen = true }
        .onDisappear { model.windowOpen = false }
        .navigationTitle("Silicium")
    }

    private func cardPosition(in size: CGSize) -> CGPoint {
        let p = model.hoverLocation
        let x = min(max(130, p.x + 150), size.width - 130)
        let y = min(max(80, size.height - p.y + 80), size.height - 80)   // AppKit : origine en bas
        return CGPoint(x: x, y: y)
    }

    private var overlayHUD: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.inspectChip ? "À l’intérieur de la puce" : (model.selection.map(ComponentInfo.shortTitle) ?? "Votre Mac, de l’intérieur"))
                        .font(.title2.weight(.medium))
                    Text(model.inspectChip ? "Vue pédagogique des unités de calcul" : "Explorez le matériel · mesures en direct")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(isOn: Binding(get: { model.showLabels }, set: { model.showLabels = $0 })) {
                    Label("Repères", systemImage: "tag")
                }
                .toggleStyle(.button).help("Afficher les noms sur le modèle")
            }
            .padding(22)
            .background(LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
            Spacer()
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Button { model.showOverview() } label: { Label("Vue d’ensemble", systemImage: "arrow.counterclockwise") }
                        .help("Revenir au matériel complet")
                    Menu {
                        ForEach(SceneCameraPreset.allCases) { preset in
                            Button(preset.rawValue) { model.setView(preset) }
                        }
                    } label: { Label("Angle", systemImage: "view.3d") }
                    Toggle(isOn: Binding(get: { model.exploded }, set: { model.exploded = $0 })) {
                        Label("Éclater", systemImage: "square.3.layers.3d")
                    }.toggleStyle(.button).help("Séparer les couches du matériel")
                    Spacer(minLength: 0)
                    Button { model.zoomStep -= 1 } label: { Image(systemName: "minus.magnifyingglass") }
                        .accessibilityLabel("Dézoomer")
                    Button { model.zoomStep += 1 } label: { Image(systemName: "plus.magnifyingglass") }
                        .accessibilityLabel("Zoomer")
                }
                .controlSize(.small)
                .padding(10).background(.regularMaterial, in: .rect(cornerRadius: 12))
                Text("Glisser pour tourner · Pincer pour zoomer · Cliquer pour explorer")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).padding(.bottom, 18)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { model.showDiagnosis = true } label: { Label("Diagnostic", systemImage: "stethoscope") }
                .help("Pourquoi mon Mac rame ?")
            Button { openSettings() } label: { Label("Réglages", systemImage: "gearshape") }
        }
    }
}
