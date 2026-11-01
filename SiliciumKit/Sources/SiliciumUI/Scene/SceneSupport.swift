import RealityKit
import AppKit
import SiliciumShared

/// Marque une entité cliquable avec la composante qu'elle représente.
struct ComponentTag: Component {
    var id: ComponentID
}

/// Entrée de la scène : tout ce qui pilote la lumière, dérivé du modèle d'app à chaque instantané.
struct SceneInput: Equatable {
    var level: [ComponentID: HealthLevel] = [:]
    var load: [ComponentID: Float] = [:]
    var perfLoads: [Float] = []
    var effLoads: [Float] = []
    var gpuUtilization: Float = 0
    var aneLoad: Float = 0
    var memoryUsed: Float = 0
    var memoryActivity: Float = 0
    var diskUsed: Float = 0
    var diskActivity: Float = 0
    var batteryCharge: Float = 0
    var batteryCharging = false
    var batteryDraw: Float = 0       // 0…1 (≈ 30 W)
    var onAC = false
    var hasBattery = true
    var netActivity: Float = 0
    var signalBars: Int = 0          // 0…3
    var chipTempC: Float = 38
    var thermalPressure: Int = 0
    var selection: ComponentID?
    var selectionRevision = 0
    var hovered: ComponentID?
    var exploded = false
    var inspectChip = false
    var reduceMotion = false
    var particles = true
}

enum Palette {
    static func rgb(_ level: HealthLevel) -> SIMD3<Float> {
        switch level {
        case .ok: [0.06, 0.90, 0.58]
        case .warning: [1.00, 0.70, 0.12]
        case .critical: [1.00, 0.22, 0.22]
        case .unavailable: [0.28, 0.34, 0.46]
        }
    }
    static let accent: SIMD3<Float> = [0.30, 0.60, 1.0]
    static func ns(_ c: SIMD3<Float>, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: alpha)
    }
}

/// Une surface qui s'illumine. L'intensité est lissée à chaque image pour que 1 mesure/s paraisse fluide à 60 i/s.
@MainActor
final class GlowPart {
    let entity: Entity
    let component: ComponentID
    var base: PhysicallyBasedMaterial
    var level: Float = 0
    var target: Float = 0
    var color: SIMD3<Float> = Palette.rgb(.ok)
    var targetColor: SIMD3<Float> = Palette.rgb(.ok)
    var idle: Float
    var peak: Float
    var pulse = false
    var boost: Float = 0        // survol / sélection
    var emissiveTexture: TextureResource?
    private var lastWritten: (Float, SIMD3<Float>) = (-1, .zero)

    init(entity: Entity, component: ComponentID, base: PhysicallyBasedMaterial, idle: Float = 0.12, peak: Float = 2.2) {
        self.entity = entity; self.component = component; self.base = base
        self.idle = idle; self.peak = peak
    }

    func step(dt: Float, time: Float, reduceMotion: Bool) {
        let k = min(1, dt * 7)
        level += (target - level) * k
        color += (targetColor - color) * min(1, dt * 5)
        var intensity = idle + (peak - idle) * level
        if pulse && !reduceMotion { intensity *= 0.78 + 0.22 * sin(time * 3.0) }
        intensity += boost * 0.16
        if abs(intensity - lastWritten.0) < 0.004 && simd_distance_sq(color, lastWritten.1) < 1e-5 { return }
        lastWritten = (intensity, color)
        var m = base
        m.emissiveColor = .init(color: Palette.ns(color), texture: emissiveTexture.map { .init($0) })
        m.emissiveIntensity = max(0, intensity)
        if var mc = entity.components[ModelComponent.self] { mc.materials = [m]; entity.components.set(mc) }
    }
}

@inline(__always) private func simd_distance_sq(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d = a - b; return (d * d).sum()
}

/// Particules qui voyagent le long d'un chemin (bande passante mémoire, puissance batterie…).
@MainActor
final class FlowPath {
    let points: [SIMD3<Float>]
    let particles: [ModelEntity]
    var phase: [Float]
    var speed: Float = 0.0
    var activity: Float = 0
    let length: Float
    let parent: Entity
    var color: SIMD3<Float>
    private var cumulative: [Float] = [0]

    init(points: [SIMD3<Float>], count: Int, parent: Entity, color: SIMD3<Float>, size: Float = 0.0038) {
        self.points = points
        self.parent = parent
        self.color = color
        var total: Float = 0
        for i in 1..<points.count { total += simd_length(points[i] - points[i - 1]); cumulative.append(total) }
        length = total
        var mat = UnlitMaterial(color: Palette.ns(color))
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        particles = (0..<count).map { _ in
            let e = ModelEntity(mesh: .generateSphere(radius: size), materials: [mat])
            e.isEnabled = false
            parent.addChild(e)
            return e
        }
        phase = (0..<count).map { Float($0) / Float(count) }
    }

    func setColor(_ c: SIMD3<Float>) {
        guard c != color else { return }
        color = c
        var mat = UnlitMaterial(color: Palette.ns(c))
        mat.blending = .transparent(opacity: .init(floatLiteral: 0.95))
        for p in particles { p.model?.materials = [mat] }
    }

    func position(at t: Float) -> SIMD3<Float> {
        let d = (t - floor(t)) * length
        var i = 1
        while i < cumulative.count - 1 && cumulative[i] < d { i += 1 }
        let seg = max(0.0001, cumulative[i] - cumulative[i - 1])
        return points[i - 1] + (points[i] - points[i - 1]) * ((d - cumulative[i - 1]) / seg)
    }

    func step(dt: Float, enabled: Bool) {
        let n = particles.count
        for i in 0..<n {
            let visible = enabled && activity > 0.02 && Float(i) / Float(n) < activity
            particles[i].isEnabled = visible
            guard visible else { continue }
            phase[i] += speed * dt / max(0.1, length)
            if phase[i] > 1 { phase[i] -= 1 }
            particles[i].position = position(at: phase[i])
            let fade = sin(phase[i] * .pi)
            particles[i].scale = SIMD3(repeating: 0.4 + 0.9 * fade)
        }
    }
}
