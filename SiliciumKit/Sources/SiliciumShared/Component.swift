import Foundation

/// Famille de composantes modélisées en 3D et dans le moteur de santé.
public enum ComponentID: String, CaseIterable, Sendable, Codable, Identifiable, Hashable {
    case chip, performanceCores, efficiencyCores, gpu, neuralEngine
    case memory, ssd, battery, wireless, power

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chip: "Puce M5"
        case .performanceCores: "Super-cœurs"
        case .efficiencyCores: "Cœurs d'efficacité"
        case .gpu: "GPU"
        case .neuralEngine: "Neural Engine"
        case .memory: "Mémoire unifiée"
        case .ssd: "SSD"
        case .battery: "Batterie"
        case .wireless: "Wi-Fi / Bluetooth"
        case .power: "Alimentation"
        }
    }

    public var symbol: String {
        switch self {
        case .chip: "cpu"
        case .performanceCores: "bolt.fill"
        case .efficiencyCores: "leaf.fill"
        case .gpu: "display"
        case .neuralEngine: "brain"
        case .memory: "memorychip"
        case .ssd: "internaldrive"
        case .battery: "battery.100percent"
        case .wireless: "wifi"
        case .power: "powerplug"
        }
    }

    /// Poids par défaut dans le score global (section 4 du plan).
    public var defaultWeight: Double {
        switch self {
        case .chip: 3
        case .memory: 3
        case .ssd, .battery, .performanceCores, .efficiencyCores: 2
        case .gpu, .wireless: 1
        case .neuralEngine, .power: 0
        }
    }

    /// Touche numérique 1…9 pour sauter vers la composante.
    public var shortcutKey: Character? {
        guard let i = ComponentID.allCases.firstIndex(of: self), i < 9 else { return nil }
        return Character(String(i + 1))
    }
}

public enum HealthLevel: String, Sendable, Codable, Comparable {
    case ok, warning, critical
    case unavailable

    public var label: String {
        switch self {
        case .ok: "OK"
        case .warning: "Attention"
        case .critical: "Problème"
        case .unavailable: "Indisponible"
        }
    }

    public var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .unavailable: "questionmark.circle"
        }
    }

    private var order: Int {
        switch self { case .unavailable: 0; case .ok: 1; case .warning: 2; case .critical: 3 }
    }
    public static func < (a: Self, b: Self) -> Bool { a.order < b.order }

    /// 80–100 vert, 50–79 ambre, 0–49 rouge.
    public init(score: Double) {
        self = score >= 80 ? .ok : (score >= 50 ? .warning : .critical)
    }
}
