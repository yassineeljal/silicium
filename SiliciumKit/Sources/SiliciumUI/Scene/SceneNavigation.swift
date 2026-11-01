import SwiftUI
import Observation
import SiliciumShared

public enum SceneCameraPreset: String, CaseIterable, Identifiable {
    case perspective = "Perspective"
    case top = "Vue du dessus"
    public var id: String { rawValue }
}

struct SceneMarker: Identifiable, Equatable {
    let id: ComponentID
    let point: CGPoint
}

/// Projection updates are isolated from sensor state and the NSViewRepresentable.
@MainActor @Observable
final class SceneAnnotations {
    var markers: [SceneMarker] = []
}

struct ComponentMarkers: View {
    let model: AppModel

    var body: some View {
        GeometryReader { geo in
            let markers = arranged(in: geo.size)
            ForEach(markers, id: \.marker.id) { item in
                Path { path in
                    path.move(to: item.marker.point)
                    path.addLine(to: item.label)
                }
                .stroke(.white.opacity(0.28), lineWidth: 1)
                .allowsHitTesting(false)
                Circle().fill(.white.opacity(0.8)).frame(width: 4, height: 4)
                    .position(item.marker.point).allowsHitTesting(false)
                Button { model.select(item.marker.id) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.marker.id.symbol).font(.caption)
                        Text(ComponentInfo.shortTitle(item.marker.id)).font(.caption.weight(.medium))
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(model.selection == item.marker.id ? 0.6 : 0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Voir \(item.marker.id.title)")
                .help("Afficher les mesures de \(item.marker.id.title)")
                .position(item.label)
            }
        }
    }

    private struct PlacedMarker {
        let marker: SceneMarker
        let label: CGPoint
    }

    private func arranged(in size: CGSize) -> [PlacedMarker] {
        guard model.showLabels else { return [] }
        var placed: [PlacedMarker] = []
        for marker in model.annotations.markers {
            let p = marker.point
            guard p.x > 10, p.x < size.width - 10, p.y > 105, p.y < size.height - 90 else { continue }
            let offset: CGPoint = switch marker.id {
            case .chip: CGPoint(x: 105, y: 40)
            case .memory: CGPoint(x: 0, y: -70)
            case .ssd: CGPoint(x: -100, y: 25)
            case .power: CGPoint(x: -90, y: -45)
            case .wireless: CGPoint(x: 75, y: -35)
            case .battery: CGPoint(x: -50, y: 40)
            case .performanceCores: CGPoint(x: -85, y: -40)
            case .efficiencyCores: CGPoint(x: -90, y: 40)
            case .gpu: CGPoint(x: 100, y: -30)
            case .neuralEngine: CGPoint(x: 90, y: 35)
            }
            var label = CGPoint(x: min(size.width - 78, max(78, p.x + offset.x)),
                                y: min(size.height - 108, max(125, p.y + offset.y)))
            for _ in 0..<8 {
                if placed.contains(where: { abs($0.label.x - label.x) < 145 && abs($0.label.y - label.y) < 35 }) {
                    label.y += 37
                } else { break }
            }
            guard label.y < size.height - 90 else { continue }
            placed.append(PlacedMarker(marker: marker, label: label))
        }
        return placed
    }
}

struct ExplorerSidebar: View {
    let model: AppModel
    private let hardware: [ComponentID] = [.chip, .memory, .ssd, .battery, .wireless, .power]
    private let silicon: [ComponentID] = [.performanceCores, .efficiencyCores, .gpu, .neuralEngine]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("EXPLORER").font(.caption2.weight(.semibold)).tracking(1.6)
                    .foregroundStyle(.secondary).padding(.horizontal, 12).padding(.top, 22).padding(.bottom, 10)
                Button { model.showOverview() } label: {
                    Label("Vue d’ensemble", systemImage: "square.grid.2x2")
                        .font(.callout.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(model.selection == nil ? Theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 9))
                }.buttonStyle(.plain)
                Text("MATÉRIEL").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(.tertiary).padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 5)
                ForEach(hardware) { row($0) }
                Text("DANS LA PUCE").font(.system(size: 10, weight: .semibold)).tracking(1.4)
                    .foregroundStyle(.tertiary).padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 5)
                ForEach(silicon) { row($0) }
                Text("Choisis un composant pour le situer et voir ses mesures.")
                    .font(.caption).foregroundStyle(.secondary).padding(12).padding(.top, 14)
            }
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden)
        .background(.background.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Navigation des composants")
    }

    private func row(_ id: ComponentID) -> some View {
        let selected = model.selection == id
        return Button { model.select(id) } label: {
            HStack(spacing: 9) {
                Image(systemName: id.symbol).frame(width: 18).foregroundStyle(selected ? Theme.accent : .secondary)
                Text(ComponentInfo.shortTitle(id)).font(.callout)
                Spacer(minLength: 0)
                if let health = model.health(id), health.level == .warning || health.level == .critical {
                    Image(systemName: health.level.symbol).font(.caption2).foregroundStyle(health.level.color)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(selected ? Theme.accent.opacity(0.12) : .clear, in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(ComponentInfo.purpose(id))
    }
}
