import RealityKit
import AppKit
import SiliciumShared

/// Construit la maquette 3D « carte mère éclatée » de façon procédurale (primitives RealityKit).
/// Axes : x = droite, y = haut, z = vers le spectateur. Unités ≈ mètres de maquette.
@MainActor
final class BoardRig {
    let root = Entity()

    // Couches déplaçables pour la vue éclatée.
    var boardLayer = Entity()
    var batteryLayer = Entity()
    var bottomPlate = Entity()
    var lidLayer = Entity()
    var siliconLayer = Entity()
    /// Échelle de la barre de remplissage SSD à 100 % (0,25 en procédural, 1 avec le modèle Blender).
    var diskFullScale: Float = 0.25
    private(set) var usesBlenderModel = false

    var parts: [ComponentID: [GlowPart]] = [:]
    var perfTiles: [GlowPart] = []
    var effTiles: [GlowPart] = []
    var gpuTiles: [GlowPart] = []
    var aneTile: GlowPart?
    var memorySegments: [GlowPart] = []
    var diskBars: [(pivot: Entity, part: GlowPart)] = []
    var batteryCells: [GlowPart] = []
    var wifiBars: [GlowPart] = []
    var portParts: [GlowPart] = []
    var chipParts: [GlowPart] = []

    var outlines: [ComponentID: Entity] = [:]
    var focus: [ComponentID: (center: SIMD3<Float>, radius: Float)] = [:]
    var flows: [String: FlowPath] = [:]
    var halo = ModelEntity()
    var haloMaterialColor: SIMD3<Float> = [0, 0, 0]
    var gpuCoreCount: Int

    static let explodedLid: Float = 0.20
    static let explodedBattery = SIMD3<Float>(0, -0.20, 0.10)
    static let explodedPlate = SIMD3<Float>(0, -0.42, 0.05)

    init(gpuCoreCount: Int, model: Entity? = nil) {
        self.gpuCoreCount = gpuCoreCount
        ComponentTag.registerComponent()
        if let model { adopt(model) } else { build() }
    }

    // MARK: Modèle Blender (USDZ)

    /// Charge `Silicium.usdz` (généré par `tools/blender/build_model.py`) ; `nil` si absent → maquette procédurale.
    static func loadModel() -> Entity? {
        guard let url = Bundle.main.url(forResource: "Silicium", withExtension: "usdz") else { return nil }
        return try? Entity.load(contentsOf: url)
    }

    private func index(of name: String) -> Int {
        Int(name.split(separator: "_").last(where: { Int($0) != nil }).flatMap { Int($0) } ?? 0)
    }

    private func adopt(_ model: Entity) {
        usesBlenderModel = true
        root.addChild(model)
        // USD keeps Blender's Z-up transform on an ancestor. Identity containers
        // let camera anchors, highlights and exploded offsets all use app Y-up.
        func wrap(_ name: String, in parent: Entity) -> Entity {
            let imported = root.findEntity(named: name)
            let container = Entity()
            container.name = "RIG__" + name
            parent.addChild(container)
            if let imported { container.addChild(imported, preservingWorldTransform: true) }
            return container
        }
        boardLayer = wrap("LAYER__board", in: root)
        batteryLayer = wrap("LAYER__battery", in: root)
        bottomPlate = wrap("LAYER__chassis", in: root)
        lidLayer = wrap("LAYER__lid", in: boardLayer)
        siliconLayer = wrap("LAYER__silicon", in: boardLayer)
        var componentBounds: [ComponentID: BoundingBox] = [:]
        var pieceBounds: [ComponentID: [BoundingBox]] = [:]
        func meshes(_ e: Entity) -> [Entity] {
            (e.components.has(ModelComponent.self) ? [e] : []) + e.children.flatMap { meshes($0) }
        }
        func walk(_ e: Entity) {
            let fields = e.name.components(separatedBy: "__")
            if fields.count >= 3, fields[0] == "PART", let id = ComponentID(rawValue: fields[1]) {
                let b = e.visualBounds(relativeTo: root)
                componentBounds[id] = componentBounds[id].map { $0.union(b) } ?? b
                pieceBounds[id, default: []].append(b)
                for mesh in meshes(e) {
                    tagged(mesh, id)
                    // Only the educational die emits light. Keep the imported physical materials.
                    if [.performanceCores, .efficiencyCores, .gpu, .neuralEngine].contains(id),
                       let base = mesh.components[ModelComponent.self]?.materials.first as? PhysicallyBasedMaterial {
                        let part = GlowPart(entity: mesh, component: id, base: base, idle: 0.015, peak: 0.45)
                        parts[id, default: []].append(part)
                        switch id {
                        case .performanceCores: perfTiles.append(part)
                        case .efficiencyCores: effTiles.append(part)
                        case .gpu: gpuTiles.append(part)
                        case .neuralEngine: aneTile = part
                        default: break
                        }
                    }
                }
            }
            for c in e.children { walk(c) }
        }
        walk(root)
        // Sort by the numeric PART name, independent of USD traversal order.
        func order(_ a: GlowPart, _ b: GlowPart) -> Bool {
            index(of: a.entity.parent?.name ?? a.entity.name) < index(of: b.entity.parent?.name ?? b.entity.name)
        }
        perfTiles.sort(by: order); effTiles.sort(by: order); gpuTiles.sort(by: order)
        for (id, b) in componentBounds {
            focus[id] = (b.center, max(b.extents.x, b.extents.z) / 2)
            let outline = Entity()
            let boxes = [.memory, .ssd, .power].contains(id) ? (pieceBounds[id] ?? [b]) : [b]
            for box in boxes {
                let center = box.center
                let w = box.extents.x + 0.010, d = box.extents.z + 0.010
                let t: Float = 0.0011
                let y = box.max.y + 0.002
                let mat = UnlitMaterial(color: NSColor(srgbRed: 0.45, green: 0.72, blue: 0.87, alpha: 1))
                // Short corner brackets leave the hardware visible.
                for sx: Float in [-1, 1] { for sz: Float in [-1, 1] {
                    let length = min(0.026, min(w, d) * 0.24)
                    for (size, pos) in [
                        (SIMD3<Float>(length, t, t), SIMD3<Float>(center.x + sx * (w / 2 - length / 2), y, center.z + sz * d / 2)),
                        (SIMD3<Float>(t, t, length), SIMD3<Float>(center.x + sx * w / 2, y, center.z + sz * (d / 2 - length / 2)))
                    ] {
                        let line = ModelEntity(mesh: .generateBox(size: size), materials: [mat])
                        line.position = pos
                        outline.addChild(line)
                    }
                } }
            }
            (id == .battery ? batteryLayer : boardLayer).addChild(outline)
            outline.isEnabled = false
            outlines[id] = outline
        }
        siliconLayer.isEnabled = false
    }

    func setInspection(_ enabled: Bool) {
        guard usesBlenderModel else { return }
        siliconLayer.isEnabled = enabled
        lidLayer.isEnabled = !enabled
    }

    func markerPosition(for id: ComponentID) -> SIMD3<Float>? {
        guard let f = focus[id] else { return nil }
        return f.center + (id == .battery ? batteryLayer.position : .zero) + [0, 0.014, 0]
    }

    // MARK: Matériaux

    private var patternCache: [String: TextureResource] = [:]
    func texture(_ p: ProceduralTextures.Pattern) -> TextureResource? {
        let k = "\(p)"
        if let t = patternCache[k] { return t }
        guard let t = ProceduralTextures.emissive(p) else { return nil }
        patternCache[k] = t; return t
    }

    func pbr(_ c: NSColor, rough: Float = 0.6, metal: Float = 0.0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        return m
    }

    private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

    @discardableResult
    private func box(_ size: SIMD3<Float>, at p: SIMD3<Float>, radius: Float = 0.002, mat: PhysicallyBasedMaterial, in parent: Entity, name: String = "") -> ModelEntity {
        let e = ModelEntity(mesh: .generateBox(size: size, cornerRadius: min(radius, min(size.x, size.y, size.z) * 0.45)), materials: [mat])
        e.position = p
        e.name = name
        parent.addChild(e)
        return e
    }

    private func glow(_ id: ComponentID, size: SIMD3<Float>, at p: SIMD3<Float>, radius: Float = 0.002, base: NSColor = NSColor(srgbRed: 0.045, green: 0.055, blue: 0.075, alpha: 1),
                      idle: Float = 0.10, peak: Float = 2.2, pattern: ProceduralTextures.Pattern? = nil, in parent: Entity, tag: Bool = true) -> GlowPart {
        let m = pbr(base, rough: 0.35, metal: 0.4)
        let e = box(size, at: p, radius: radius, mat: m, in: parent)
        if tag {
            e.components.set(ComponentTag(id: id))
            e.generateCollisionShapes(recursive: false)
        }
        let part = GlowPart(entity: e, component: id, base: m, idle: idle, peak: peak)
        if let pattern { part.emissiveTexture = texture(pattern) }
        parts[id, default: []].append(part)
        return part
    }

    func tagged(_ e: Entity, _ id: ComponentID) {
        e.components.set(ComponentTag(id: id))
        e.generateCollisionShapes(recursive: false)
    }

    private func label(_ text: String, at p: SIMD3<Float>, size: Float = 0.016, alpha: CGFloat = 0.38, in parent: Entity) {
        let mesh = MeshResource.generateText(text, extrusionDepth: 0.0004, font: .monospacedSystemFont(ofSize: CGFloat(size), weight: .semibold),
                                             containerFrame: .zero, alignment: .center, lineBreakMode: .byClipping)
        var m = UnlitMaterial(color: rgb(0.75, 0.85, 1, alpha))
        m.blending = .transparent(opacity: .init(floatLiteral: Float(alpha)))
        let e = ModelEntity(mesh: mesh, materials: [m])
        let b = e.model!.mesh.bounds
        e.position = p - SIMD3(b.center.x, 0, 0)
        e.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        parent.addChild(e)
    }

    // MARK: Construction

    private func build() {
        root.addChild(boardLayer); root.addChild(batteryLayer); root.addChild(bottomPlate); root.addChild(lidLayer)
        buildBoard()
        buildChip()
        buildMemory()
        buildStorage()
        buildWireless()
        buildPorts()
        buildBattery()
        buildBottomPlate()
        buildDetails()
        buildHalo()
        buildFlows()
        buildOutlines()
    }

    private func buildBoard() {
        // Carte principale
        var boardMat = pbr(rgb(1, 1, 1), rough: 0.55, metal: 0.25)
        if let tex = ProceduralTextures.pcb() { boardMat.baseColor = .init(tint: .white, texture: .init(tex)) }
        box([1.00, 0.020, 0.46], at: [0, -0.010, -0.07], radius: 0.012, mat: boardMat, in: boardLayer, name: "board")
        // Liseré de bord
        let edge = pbr(rgb(0.10, 0.13, 0.19), rough: 0.35, metal: 0.8)
        box([1.0, 0.003, 0.004], at: [0, 0.0005, -0.298], radius: 0.001, mat: edge, in: boardLayer)
        box([1.0, 0.003, 0.004], at: [0, 0.0005, 0.158], radius: 0.001, mat: edge, in: boardLayer)

        // Pistes décoratives (réseau de lignes fines)
        let trace = pbr(rgb(0.16, 0.20, 0.28), rough: 0.3, metal: 0.9)
        let tz: [Float] = [-0.27, -0.255, -0.24, 0.12, 0.135]
        for (i, z) in tz.enumerated() {
            box([0.55 + Float(i) * 0.05, 0.0012, 0.0022], at: [-0.12 + Float(i) * 0.02, 0.0016, z], radius: 0.0005, mat: trace, in: boardLayer)
        }
        for i in 0..<6 {
            let x = -0.46 + Float(i) * 0.016
            box([0.0022, 0.0012, 0.20], at: [x, 0.0016, -0.07], radius: 0.0005, mat: trace, in: boardLayer)
        }
        for i in 0..<8 {
            let x = 0.40 + Float(i) * 0.0125
            box([0.0022, 0.0012, 0.16 - Float(i % 3) * 0.02], at: [x, 0.0016, -0.04], radius: 0.0005, mat: trace, in: boardLayer)
        }
        // Vis de fixation
        let screw = pbr(rgb(0.30, 0.34, 0.42), rough: 0.25, metal: 1)
        for (x, z) in [(-0.47, -0.275), (0.47, -0.275), (-0.47, 0.135), (0.47, 0.135)] as [(Float, Float)] {
            let s = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.012), materials: [screw])
            s.position = [x, 0.002, z]; boardLayer.addChild(s)
        }
        // Petits composants passifs
        let passive = pbr(rgb(0.09, 0.10, 0.13), rough: 0.5, metal: 0.5)
        for i in 0..<16 {
            let x = -0.30 + Float(i % 8) * 0.014
            let z: Float = i < 8 ? 0.065 : 0.083
            box([0.008, 0.004, 0.005], at: [x, 0.004, z], radius: 0.001, mat: passive, in: boardLayer)
        }
        label("SILICIUM · M5", at: [-0.18, 0.0035, 0.14], size: 0.014, alpha: 0.30, in: boardLayer)
    }

    private func buildChip() {
        let chipC: SIMD3<Float> = [-0.08, 0, -0.10]
        let chipRoot = Entity(); chipRoot.position = chipC; boardLayer.addChild(chipRoot)

        // Substrat
        let sub = box([0.30, 0.012, 0.30], at: [0, 0.007, 0], radius: 0.006, mat: pbr(rgb(0.07, 0.085, 0.11), rough: 0.45, metal: 0.55), in: chipRoot, name: "substrate")
        tagged(sub, .chip)
        let subPart = GlowPart(entity: sub, component: .chip, base: sub.model!.materials[0] as! PhysicallyBasedMaterial, idle: 0.0, peak: 0.8)
        subPart.base.emissiveColor = .init(color: .white)
        chipParts.append(subPart); parts[.chip, default: []].append(subPart)
        // Plots de bord (BGA stylisé)
        let pad = pbr(rgb(0.55, 0.50, 0.30), rough: 0.3, metal: 1)
        for i in 0..<14 {
            let t = -0.135 + Float(i) * 0.0208
            for z in [-0.142, 0.142] as [Float] { box([0.008, 0.002, 0.004], at: [t, 0.0135, z], radius: 0.0005, mat: pad, in: chipRoot) }
            for x in [-0.142, 0.142] as [Float] { box([0.004, 0.002, 0.008], at: [x, 0.0135, t], radius: 0.0005, mat: pad, in: chipRoot) }
        }

        // Puce silicium (die)
        var dieMat = pbr(rgb(1, 1, 1), rough: 0.16, metal: 0.9)
        if let tex = ProceduralTextures.die() { dieMat.baseColor = .init(tint: .white, texture: .init(tex)) }
        let die = box([0.236, 0.010, 0.236], at: [0, 0.018, 0], radius: 0.003, mat: dieMat, in: chipRoot, name: "die")
        tagged(die, .chip)
        let dieY: Float = 0.0245
        let dieRoot = Entity(); dieRoot.position = [0, dieY, 0]; chipRoot.addChild(dieRoot)

        // Super-cœurs : 2×2 en haut à gauche
        let pSize: SIMD3<Float> = [0.050, 0.004, 0.050]
        for r in 0..<2 { for c in 0..<2 {
            let p = glow(.performanceCores, size: pSize, at: [-0.088 + Float(c) * 0.056, 0, -0.088 + Float(r) * 0.056], radius: 0.003, peak: 1.7, in: dieRoot)
            perfTiles.append(p)
        } }
        // Cœurs d'efficacité : 3×2 en bas à gauche
        let eSize: SIMD3<Float> = [0.030, 0.004, 0.034]
        for r in 0..<2 { for c in 0..<3 {
            let p = glow(.efficiencyCores, size: eSize, at: [-0.095 + Float(c) * 0.036, 0, 0.005 + Float(r) * 0.040], radius: 0.002, peak: 2.0, pattern: .cells, in: dieRoot)
            effTiles.append(p)
        } }
        // Neural Engine : bloc en bas à droite avec micro-cellules
        let ane = glow(.neuralEngine, size: [0.100, 0.004, 0.034], at: [0.050, 0, 0.088], radius: 0.002, peak: 2.2, pattern: .dots, in: dieRoot)
        aneTile = ane
        let cell = pbr(rgb(0.02, 0.03, 0.05), rough: 0.3, metal: 0.6)
        for i in 0..<8 { box([0.008, 0.0012, 0.026], at: [0.012 + Float(i) * 0.0118, 0.0024, 0.088], radius: 0.0004, mat: cell, in: dieRoot) }
        // GPU : colonnes de tuiles à droite
        let gpuRows = max(2, gpuCoreCount / 2)
        let gh = (0.150 - 0.004 * Float(gpuRows - 1)) / Float(gpuRows)
        for r in 0..<gpuRows { for c in 0..<2 {
            let z = -0.099 + Float(r) * (gh + 0.004) + gh / 2
            let p = glow(.gpu, size: [0.040, 0.004, gh], at: [0.024 + Float(c) * 0.044, 0, z], radius: 0.002, peak: 2.2, pattern: .fine, in: dieRoot)
            gpuTiles.append(p)
        } }
        // Fabric / contrôleurs mémoire : bandes décoratives
        let deco = pbr(rgb(0.07, 0.10, 0.16), rough: 0.3, metal: 0.7)
        box([0.012, 0.0025, 0.200], at: [-0.003, 0.0012, -0.005], radius: 0.0008, mat: deco, in: dieRoot)
        box([0.060, 0.0025, 0.010], at: [-0.060, 0.0012, -0.026 + 0.0], radius: 0.0008, mat: deco, in: dieRoot)
        label("M5", at: [0.02, 0.0245, 0.0], size: 0.012, alpha: 0.0, in: dieRoot)

        // Cadre dissipateur (heat spreader) : se soulève en vue éclatée
        lidLayer.position = chipC
        let lidMat = pbr(rgb(0.55, 0.60, 0.68), rough: 0.22, metal: 1)
        let t: Float = 0.016
        box([0.28, 0.006, t], at: [0, 0.034, -0.132], radius: 0.002, mat: lidMat, in: lidLayer)
        box([0.28, 0.006, t], at: [0, 0.034, 0.132], radius: 0.002, mat: lidMat, in: lidLayer)
        box([t, 0.006, 0.248], at: [-0.132, 0.034, 0], radius: 0.002, mat: lidMat, in: lidLayer)
        box([t, 0.006, 0.248], at: [0.132, 0.034, 0], radius: 0.002, mat: lidMat, in: lidLayer)
        // Vitre fumée du boîtier (translucide)
        var glass = pbr(rgb(0.4, 0.55, 0.8, 1), rough: 0.05, metal: 0.2)
        glass.blending = .transparent(opacity: .init(floatLiteral: 0.10))
        let pane = ModelEntity(mesh: .generateBox(size: [0.27, 0.002, 0.27], cornerRadius: 0.003), materials: [glass])
        pane.position = [0, 0.0375, 0]; lidLayer.addChild(pane)
    }

    private func buildMemory() {
        // Deux paquets LPDDR de part et d'autre de la puce, 8 segments chacun (16 segments = 16 Go)
        let pkgMat = pbr(rgb(0.055, 0.065, 0.085), rough: 0.4, metal: 0.5)
        for (i, x) in ([-0.355, 0.195] as [Float]).enumerated() {
            let c = Entity(); c.position = [x, 0, -0.10]; boardLayer.addChild(c)
            let pkg = box([0.130, 0.012, 0.240], at: [0, 0.007, 0], radius: 0.005, mat: pkgMat, in: c)
            tagged(pkg, .memory)
            for s in 0..<8 {
                let z = -0.100 + Float(s) * 0.0285
                let seg = glow(.memory, size: [0.098, 0.004, 0.0215], at: [0, 0.0145, z + 0.012], radius: 0.0015, idle: 0.02, peak: 2.0, pattern: .stripes, in: c)
                seg.entity.name = "mem\(i)-\(s)"
                memorySegments.append(seg)
            }
            label(i == 0 ? "LPDDR5X · 8 Go" : "LPDDR5X · 8 Go", at: [0, 0.0155, 0.115], size: 0.011, alpha: 0.35, in: c)
        }
    }

    private func buildStorage() {
        // Deux puces NAND avec une barre de remplissage (espace utilisé)
        let nandMat = pbr(rgb(0.06, 0.07, 0.09), rough: 0.4, metal: 0.5)
        for (i, x) in ([-0.30, 0.07] as [Float]).enumerated() {
            let c = Entity(); c.position = [x, 0, 0.065]; boardLayer.addChild(c)
            let nand = box([0.30, 0.010, 0.085], at: [0.15, 0.006, 0], radius: 0.004, mat: nandMat, in: c)
            tagged(nand, .ssd)
            // Barre de remplissage ancrée à gauche
            let pivot = Entity(); pivot.position = [-0.125, 0.0125, 0]; c.addChild(pivot)
            let track = pbr(rgb(0.02, 0.03, 0.05), rough: 0.5, metal: 0.2)
            box([0.250, 0.0012, 0.020], at: [0.125, -0.0008, 0], radius: 0.0005, mat: track, in: pivot)
            let fillMat = pbr(rgb(0.04, 0.05, 0.07), rough: 0.35, metal: 0.4)
            let fill = ModelEntity(mesh: .generateBox(size: [1, 0.004, 0.020], cornerRadius: 0.0015), materials: [fillMat])
            fill.position = [0.5, 0, 0]
            let inner = Entity(); inner.addChild(fill); inner.scale = [0.250, 1, 1]
            pivot.addChild(inner)
            fill.components.set(ComponentTag(id: .ssd))
            let part = GlowPart(entity: fill, component: .ssd, base: fillMat, idle: 0.2, peak: 2.0)
            parts[.ssd, default: []].append(part)
            diskBars.append((inner, part))
            // Pastilles de contrôleur
            let led = glow(.ssd, size: [0.016, 0.004, 0.016], at: [0.125, 0.0125, -0.028], radius: 0.002, idle: 0.1, peak: 2.2, in: c)
            _ = led
            label(i == 0 ? "NAND" : "NAND", at: [-0.095, 0.0115, -0.030], size: 0.010, alpha: 0.35, in: c)
        }
    }

    private func buildWireless() {
        let c = Entity(); c.position = [0.33, 0, -0.245]; boardLayer.addChild(c)
        let mod = box([0.14, 0.008, 0.07], at: [0, 0.005, 0], radius: 0.004, mat: pbr(rgb(0.06, 0.08, 0.11), rough: 0.4, metal: 0.6), in: c)
        tagged(mod, .wireless)
        // Barres de signal (3) + activité
        for i in 0..<3 {
            let h: Float = 0.010 + Float(i) * 0.010
            let b = glow(.wireless, size: [0.014, h, 0.014], at: [-0.035 + Float(i) * 0.024, 0.009 + h / 2, 0], radius: 0.002, idle: 0.1, peak: 2.1, pattern: .cells, in: c)
            wifiBars.append(b)
        }
        let a = glow(.wireless, size: [0.10, 0.003, 0.004], at: [-0.01, 0.0035, -0.045], radius: 0.001, idle: 0.2, peak: 1.7, in: c)
        wifiBars.append(a)
        label("Wi-Fi 7 · BT", at: [0.0, 0.0095, 0.052], size: 0.010, alpha: 0.35, in: c)
    }

    private func buildPorts() {
        // MagSafe + 2 USB-C sur le bord gauche
        let port = pbr(rgb(0.09, 0.10, 0.12), rough: 0.3, metal: 0.8)
        let specs: [(Float, Float, Float)] = [(-0.2, 0.040, 0.012), (-0.07, 0.034, 0.010), (0.01, 0.034, 0.010)]
        for (i, s) in specs.enumerated() {
            let (z, w, h) = s
            let m = pbr(rgb(0.07, 0.08, 0.10), rough: 0.35, metal: 0.7)
            let e = box([0.050, h, w], at: [-0.515, h / 2 + 0.003, z], radius: min(0.005, h * 0.45), mat: m, in: boardLayer)
            tagged(e, .power)
            let part = GlowPart(entity: e, component: .power, base: m, idle: 0.05, peak: 1.7)
            parts[.power, default: []].append(part)
            portParts.append(part)
            _ = i
        }
        _ = port
        label("MagSafe  USB-C", at: [-0.435, 0.0035, 0.07], size: 0.0085, alpha: 0.32, in: boardLayer)
    }

    private func buildBattery() {
        // Dalle batterie : 6 cellules qui se remplissent selon la charge
        batteryLayer.position = [0, 0, 0]
        let casing = box([0.98, 0.016, 0.175], at: [0, -0.002, 0.275], radius: 0.008, mat: pbr(rgb(0.045, 0.05, 0.065), rough: 0.5, metal: 0.4), in: batteryLayer)
        tagged(casing, .battery)
        for i in 0..<6 {
            let x = -0.395 + Float(i) * 0.158
            let cell = glow(.battery, size: [0.140, 0.006, 0.140], at: [x, 0.009, 0.275], radius: 0.004, idle: 0.015, peak: 1.15, pattern: .weave, in: batteryLayer)
            cell.entity.name = "cell\(i)"
            batteryCells.append(cell)
        }
        label("Li-Po · 6 cellules", at: [0, 0.007, 0.37], size: 0.011, alpha: 0.32, in: batteryLayer)
    }

    private func buildBottomPlate() {
        // Châssis : cadre métal brossé fin autour de la maquette (se détache en vue éclatée)
        let frame = pbr(rgb(0.30, 0.34, 0.42), rough: 0.28, metal: 1)
        let t: Float = 0.012
        box([1.06, 0.006, t], at: [0, -0.026, -0.318], radius: 0.003, mat: frame, in: bottomPlate)
        box([1.06, 0.006, t], at: [0, -0.026, 0.378], radius: 0.003, mat: frame, in: bottomPlate)
        box([t, 0.006, 0.70], at: [-0.524, -0.026, 0.03], radius: 0.003, mat: frame, in: bottomPlate)
        box([t, 0.006, 0.70], at: [0.524, -0.026, 0.03], radius: 0.003, mat: frame, in: bottomPlate)
    }

    /// Composants secondaires : donnent l'échelle et le réalisme d'une vraie carte.
    private func buildDetails() {
        let can = pbr(rgb(0.55, 0.60, 0.68), rough: 0.30, metal: 1)
        // Blindage perforé (droite)
        let shield = box([0.17, 0.010, 0.13], at: [0.385, 0.0065, 0.04], radius: 0.002, mat: can, in: boardLayer)
        _ = shield
        let groove = pbr(rgb(0.10, 0.12, 0.16), rough: 0.5, metal: 0.8)
        for i in 0..<9 { for j in 0..<6 {
            box([0.008, 0.0015, 0.008], at: [0.325 + Float(i) * 0.015, 0.0125, -0.005 + Float(j) * 0.0145], radius: 0.002, mat: groove, in: boardLayer)
        } }
        // Inductances de puissance
        let inductor = pbr(rgb(0.16, 0.17, 0.20), rough: 0.5, metal: 0.6)
        let copper = pbr(rgb(0.62, 0.38, 0.22), rough: 0.35, metal: 1)
        for i in 0..<5 {
            let x = 0.31 + Float(i) * 0.034
            box([0.026, 0.014, 0.026], at: [x, 0.008, -0.135], radius: 0.003, mat: inductor, in: boardLayer)
            box([0.026, 0.002, 0.006], at: [x, 0.0155, -0.135], radius: 0.001, mat: copper, in: boardLayer)
        }
        // Condensateurs céramiques autour de la puce et des mémoires
        let mlcc = pbr(rgb(0.45, 0.36, 0.20), rough: 0.4, metal: 0.7)
        for r in 0..<2 { for i in 0..<14 {
            box([0.006, 0.004, 0.011], at: [-0.22 + Float(i) * 0.0105, 0.004, -0.275 + Float(r) * 0.014], radius: 0.001, mat: mlcc, in: boardLayer)
        } }
        for i in 0..<10 {
            box([0.011, 0.004, 0.006], at: [0.145 + Float(i) * 0.0125, 0.004, 0.058], radius: 0.001, mat: mlcc, in: boardLayer)
        }
        // Condensateurs tantale (grosses cuves sombres)
        let tantalum = pbr(rgb(0.07, 0.08, 0.10), rough: 0.5, metal: 0.3)
        let strap = pbr(rgb(0.7, 0.6, 0.3), rough: 0.3, metal: 1)
        for i in 0..<4 {
            let x = 0.30 + Float(i) * 0.04
            box([0.030, 0.008, 0.016], at: [x, 0.006, 0.125], radius: 0.002, mat: tantalum, in: boardLayer)
            box([0.004, 0.0085, 0.016], at: [x + 0.012, 0.006, 0.125], radius: 0.0005, mat: strap, in: boardLayer)
        }
        // Connecteurs plats (FPC) avec rangées de broches dorées
        let conn = pbr(rgb(0.05, 0.05, 0.06), rough: 0.5, metal: 0.2)
        let pin = pbr(rgb(0.85, 0.68, 0.30), rough: 0.25, metal: 1)
        for k in 0..<3 {
            let x = -0.40 + Float(k) * 0.13
            box([0.10, 0.006, 0.014], at: [x, 0.004, 0.137], radius: 0.001, mat: conn, in: boardLayer)
            for i in 0..<24 { box([0.0016, 0.0015, 0.008], at: [x - 0.046 + Float(i) * 0.004, 0.0078, 0.137], radius: 0.0003, mat: pin, in: boardLayer) }
        }
        // Bus lumineux discrets entre mémoires et puce (guident l'œil)
        let busMat = pbr(rgb(0.02, 0.04, 0.07), rough: 0.4, metal: 0.5)
        for (x0, x1) in [(-0.285, -0.235), (0.07, 0.13)] as [(Float, Float)] {
            for k in 0..<8 {
                let z = -0.135 + Float(k) * 0.0075
                var m = busMat; m.emissiveColor = .init(color: Palette.ns(Palette.accent)); m.emissiveIntensity = 0.5
                box([x1 - x0, 0.0012, 0.0022], at: [(x0 + x1) / 2, 0.0021, z], radius: 0.0005, mat: m, in: boardLayer)
            }
        }
    }

    func buildHalo() {
        var m = UnlitMaterial(color: .white)
        if let tex = Self.radialGradientTexture() {
            m.color = .init(tint: .white, texture: .init(tex))
            m.blending = .transparent(opacity: .init(scale: 0, texture: .init(tex)))
        }
        halo = ModelEntity(mesh: .generatePlane(width: 0.9, depth: 0.9), materials: [m])
        halo.position = [-0.08, 0.06, -0.10]
        halo.scale = [0.6, 1, 0.6]
        boardLayer.addChild(halo)
    }

    static func radialGradientTexture() -> TextureResource? {
        let n = 256
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 0.9), CGColor(red: 1, green: 1, blue: 1, alpha: 0.28), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: n / 2, y: n / 2), startRadius: 0, endCenter: CGPoint(x: n / 2, y: n / 2), endRadius: CGFloat(n / 2), options: [])
        guard let img = ctx.makeImage() else { return nil }
        return try? TextureResource(image: img, options: .init(semantic: .color))
    }

    func buildFlows() {
        // Bande passante mémoire ↔ puce (deux côtés) et puissance batterie → carte
        let chipC: SIMD3<Float> = [-0.08, 0.03, -0.10]
        flows["memL"] = FlowPath(points: [[-0.355 + 0.04, 0.03, -0.10], [chipC.x - 0.13, 0.03, -0.10]], count: 12, parent: boardLayer, color: Palette.accent)
        flows["memR"] = FlowPath(points: [[0.195 - 0.04, 0.03, -0.10], [chipC.x + 0.13, 0.03, -0.10]], count: 12, parent: boardLayer, color: Palette.accent)
        flows["power"] = FlowPath(points: [[0.0, 0.03, 0.205], [0.0, 0.03, 0.12], [-0.08, 0.03, 0.12], [-0.08, 0.03, 0.05]], count: 14, parent: root, color: [1.0, 0.75, 0.25])
        flows["ssd"] = FlowPath(points: [[-0.15, 0.03, 0.10], [-0.15, 0.03, 0.02], [-0.08, 0.03, 0.02], [-0.08, 0.03, 0.05]], count: 10, parent: boardLayer, color: [0.6, 0.45, 1.0])
        flows["net"] = FlowPath(points: [[0.33, 0.03, -0.20], [0.33, 0.03, -0.10], [0.06, 0.03, -0.10]], count: 10, parent: boardLayer, color: [0.3, 0.95, 0.9])
    }

    func buildOutlines() {
        for id in ComponentID.allCases {
            let ents: [Entity] = (parts[id] ?? []).map(\.entity)
            var bounds: BoundingBox?
            for e in ents {
                let b = e.visualBounds(relativeTo: root)
                bounds = bounds.map { $0.union(b) } ?? b
            }
            guard let b = bounds else { continue }
            focus[id] = (b.center, max(b.extents.x, b.extents.z) / 2)
        }
        // Les composantes dont les pièces lumineuses ne couvrent pas tout le bloc : cadres explicites
        focus[.chip] = ([-0.08, 0.03, -0.10], 0.17)
        focus[.memory] = ([-0.08, 0.01, -0.10], 0.40)
        focus[.ssd] = ([-0.11, 0.01, 0.065], 0.28)
        focus[.battery] = ([0, 0.01, 0.275], 0.46)
        focus[.wireless] = ([0.33, 0.01, -0.245], 0.09)
        focus[.power] = ([-0.515, 0.01, -0.09], 0.14)
        focus[.performanceCores] = ([-0.08 - 0.06, 0.03, -0.10 - 0.062], 0.08)
        focus[.efficiencyCores] = ([-0.08 - 0.06, 0.03, -0.10 + 0.035], 0.07)
        focus[.gpu] = ([-0.08 + 0.046, 0.03, -0.10 - 0.012], 0.095)
        focus[.neuralEngine] = ([-0.08 + 0.05, 0.03, -0.10 + 0.088], 0.06)

        let frames: [ComponentID: (SIMD3<Float>, SIMD2<Float>)] = [
            .chip: ([-0.08, 0.026, -0.10], [0.31, 0.31]),
            .performanceCores: ([-0.08 - 0.060, 0.032, -0.10 - 0.062], [0.116, 0.116]),
            .efficiencyCores: ([-0.08 - 0.059, 0.032, -0.10 + 0.0225], [0.114, 0.082]),
            .gpu: ([-0.08 + 0.046, 0.032, -0.10 - 0.025], [0.092, 0.156]),
            .neuralEngine: ([-0.08 + 0.05, 0.032, -0.10 + 0.088], [0.106, 0.04]),
            .memory: ([-0.355, 0.02, -0.10], [0.14, 0.25]),
            .ssd: ([-0.23, 0.02, 0.065], [0.31, 0.095]),
            .battery: ([0, 0.02, 0.275], [0.99, 0.185]),
            .wireless: ([0.33, 0.02, -0.245], [0.15, 0.08]),
            .power: ([-0.515, 0.02, -0.09], [0.06, 0.34]),
        ]
        for (id, f) in frames {
            let o = Entity()
            o.position = f.0
            var mat = UnlitMaterial(color: NSColor(srgbRed: 0.7, green: 0.9, blue: 1, alpha: 1))
            mat.blending = .transparent(opacity: .init(floatLiteral: 0.95))
            let t: Float = 0.0035
            for (s, p) in [([f.1.x, 0.003, t] as SIMD3<Float>, [0, 0, -f.1.y / 2] as SIMD3<Float>), ([f.1.x, 0.003, t], [0, 0, f.1.y / 2]),
                           ([t, 0.003, f.1.y], [-f.1.x / 2, 0, 0]), ([t, 0.003, f.1.y], [f.1.x / 2, 0, 0])] {
                let bar = ModelEntity(mesh: .generateBox(size: s, cornerRadius: 0.001), materials: [mat])
                bar.position = p; o.addChild(bar)
            }
            o.isEnabled = false
            // Les contours de la batterie et de la mémoire suivent leur couche.
            (id == .battery ? batteryLayer : (id == .chip ? boardLayer : boardLayer)).addChild(o)
            if id == .chip { o.position = f.0 }
            outlines[id] = o
        }
    }

    static func radialGradient() -> TextureResource? { radialGradientTexture() }
}
