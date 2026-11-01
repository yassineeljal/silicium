import SwiftUI
import SiliciumShared

public enum Theme {
    public static let ok = Color(red: 0.20, green: 0.84, blue: 0.51)
    public static let warning = Color(red: 1.00, green: 0.72, blue: 0.20)
    public static let critical = Color(red: 1.00, green: 0.30, blue: 0.30)
    public static let neutral = Color(red: 0.45, green: 0.50, blue: 0.60)
    public static let accent = Color(red: 0.35, green: 0.62, blue: 1.00)

    public static func color(_ level: HealthLevel) -> Color {
        switch level {
        case .ok: ok
        case .warning: warning
        case .critical: critical
        case .unavailable: neutral
        }
    }

    public static func nsColor(_ level: HealthLevel) -> NSColor { NSColor(color(level)) }
}

extension HealthLevel {
    public var color: Color { Theme.color(self) }
}

/// Pastille d'état : la couleur n'est jamais seule, on affiche aussi une icône et un mot.
struct StatusBadge: View {
    let level: HealthLevel
    var compact = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.symbol)
            if !compact { Text(level.label) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(level.color)
        .padding(.horizontal, compact ? 5 : 8).padding(.vertical, 3)
        .background(level.color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level.label)
    }
}

struct GaugeBar: View {
    let value: Double
    let level: HealthLevel
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(level.color.gradient)
                    .frame(width: max(4, geo.size.width * clamp01(value)))
            }
        }
        .frame(height: 5)
        .animation(.smooth(duration: 0.6), value: value)
        .accessibilityHidden(true)
    }
}
