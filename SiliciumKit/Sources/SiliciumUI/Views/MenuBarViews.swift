import SwiftUI
import AppKit
import SiliciumShared
import SiliciumCore

/// Icône de la barre des menus : puce monochrome + pastille de couleur, ou score en chiffres.
public struct MenuBarLabel: View {
    let model: AppModel
    public init(model: AppModel) { self.model = model }
    public var body: some View {
        let level = model.hasData ? model.report.globalLevel : .unavailable
        switch model.settings.menuBarStyle {
        case .chip:
            Image(nsImage: MenuBarIconRenderer.image(level: level))
                .accessibilityLabel(model.menuBarTooltip)
        case .score:
            Image(nsImage: MenuBarIconRenderer.scoreImage(score: Int(model.report.globalScore.rounded()), level: level, hasData: model.hasData))
                .accessibilityLabel(model.menuBarTooltip)
        }
    }
}

@MainActor
enum MenuBarIconRenderer {
    static func image(level: HealthLevel) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            if let sym = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                let tinted = tint(sym, NSColor.black)
                tinted.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            }
            let dot = NSBezierPath(ovalIn: NSRect(x: 14.5, y: 0.5, width: 7, height: 7))
            Theme.nsColor(level).setFill(); dot.fill()
            return true
        }
        // Sans « template » les couleurs sont conservées ; le glyphe noir est inversé par la pastille de contraste.
        img.isTemplate = false
        return adaptive(img, level: level)
    }

    /// La barre des menus peut être claire ou sombre : on dessine le glyphe avec la couleur de texte du moment.
    private static func adaptive(_ base: NSImage, level: HealthLevel) -> NSImage {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fg = dark ? NSColor.white : NSColor.black
        let size = NSSize(width: 22, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            if let sym = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                tint(sym, fg).draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
            }
            let dot = NSBezierPath(ovalIn: NSRect(x: 14.5, y: 0.5, width: 7, height: 7))
            Theme.nsColor(level).setFill(); dot.fill()
            return true
        }
        img.isTemplate = false
        return img
    }

    static func scoreImage(score: Int, level: HealthLevel, hasData: Bool) -> NSImage {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fg = dark ? NSColor.white : NSColor.black
        let text = hasData ? "\(score)" : "–"
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: fg]
        let w = (text as NSString).size(withAttributes: attrs).width
        let size = NSSize(width: w + 14, height: 16)
        let img = NSImage(size: size, flipped: false) { _ in
            let dot = NSBezierPath(ovalIn: NSRect(x: 0, y: 4.5, width: 7, height: 7))
            Theme.nsColor(level).setFill(); dot.fill()
            (text as NSString).draw(at: NSPoint(x: 11, y: 1), withAttributes: attrs)
            return true
        }
        img.isTemplate = false
        return img
    }

    private static func tint(_ image: NSImage, _ color: NSColor) -> NSImage {
        let out = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set(); rect.fill(using: .sourceIn)
            return true
        }
        return out
    }
}

/// Détecte l'ouverture réelle du panneau pour passer en échantillonnage rapide.
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (Bool) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = ObserverView(); v.onChange = onChange; return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { (nsView as? ObserverView)?.onChange = onChange }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver); tokens = []
            guard let w = window else { onChange?(false); return }
            let nc = NotificationCenter.default
            let report: @Sendable (Notification) -> Void = { [weak self, weak w] _ in
                MainActor.assumeIsolated { self?.onChange?(w?.occlusionState.contains(.visible) ?? false) }
            }
            tokens.append(nc.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main, using: report))
            tokens.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onChange?(false) }
            })
            onChange?(w.occlusionState.contains(.visible))
        }
    }
}

/// Panneau de la barre des menus (≈ 340 × 480 pt). Lit le dernier `Snapshot` déjà en mémoire.
public struct MenuBarPanel: View {
    let model: AppModel
    let openMain: () -> Void
    let openSettings: () -> Void

    public init(model: AppModel, openMain: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.model = model; self.openMain = openMain; self.openSettings = openSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(ComponentID.allCases.filter { $0 != .neuralEngine && $0 != .power }) { id in
                        PanelRow(model: model, id: id) { model.select(id); openMain() }
                    }
                    let watch = model.report.watchlist()
                    if !watch.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("À surveiller").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 10)
                            ForEach(watch) { c in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: c.level.symbol).foregroundStyle(c.level.color)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(c.component.title).font(.callout.weight(.medium))
                                        Text(c.reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8).background(c.level.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6)
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.never)
            Divider()
            footer
        }
        .frame(width: 340, height: 480)
        .background(WindowVisibilityReader { model.panelOpen = $0 })
    }

    private var header: some View {
        HStack(spacing: 14) {
            ScoreRing(score: model.report.globalScore, level: model.report.globalLevel, size: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.hasData ? "\(Int(model.report.globalScore.rounded())) % — \(model.report.summary)" : "Analyse en cours…")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                StatusBadge(level: model.hasData ? model.report.globalLevel : .unavailable)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: openMain) { Label("Ouvrir la vue 3D", systemImage: "cube.transparent") }.buttonStyle(.borderedProminent)
            Button { model.showDiagnosis = true; openMain() } label: { Image(systemName: "stethoscope") }.help("Pourquoi mon Mac rame ?")
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape") }.help("Réglages")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Quitter Silicium")
        }
        .padding(12)
    }
}

struct PanelRow: View {
    let model: AppModel
    let id: ComponentID
    var action: () -> Void
    var body: some View {
        let h = model.health(id)
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: id.symbol).frame(width: 18).foregroundStyle(h?.level.color ?? Theme.neutral)
                    Text(id.title).font(.callout)
                    Spacer()
                    Text(h?.headline ?? "—").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    StatusBadge(level: h?.level ?? .unavailable, compact: true)
                }
                GaugeBar(value: h?.load ?? 0, level: h?.level ?? .unavailable)
            }
            .padding(.vertical, 6).padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(id.title), \(h?.headline ?? "indisponible"), \(h?.level.label ?? "")")
    }
}
