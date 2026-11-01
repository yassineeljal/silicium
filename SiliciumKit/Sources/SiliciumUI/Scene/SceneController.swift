import RealityKit
import AppKit
import Combine
import SiliciumShared

/// Vue RealityKit qui capte souris, molette, pincement et clavier.
final class SiliciumARView: ARView {
    weak var controller: SceneController?
    private var tracking: NSTrackingArea?
    private var downPoint: CGPoint = .zero
    private var dragged = false

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(t); tracking = t
    }

    private func loc(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) { controller?.pointerMoved(loc(event)) }
    override func mouseExited(with event: NSEvent) { controller?.pointerLeft() }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        downPoint = loc(event); dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = loc(event)
        if hypot(p.x - downPoint.x, p.y - downPoint.y) > 3 { dragged = true }
        guard dragged else { return }
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
            controller?.pan(dx: Float(event.deltaX), dy: Float(event.deltaY))
        } else {
            controller?.orbit(dx: Float(event.deltaX), dy: Float(event.deltaY))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !dragged { controller?.clicked(loc(event)) }
    }

    override func rightMouseDragged(with event: NSEvent) { controller?.pan(dx: Float(event.deltaX), dy: Float(event.deltaY)) }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas && !event.modifierFlags.contains(.command) {
            controller?.pan(dx: Float(event.scrollingDeltaX) * 0.6, dy: Float(event.scrollingDeltaY) * 0.6)
        } else {
            controller?.zoom(by: Float(-event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 0.01 : 0.05))
        }
    }

    override func magnify(with event: NSEvent) { controller?.zoom(by: Float(-event.magnification) * 1.6) }

    override func keyDown(with event: NSEvent) {
        guard let c = event.charactersIgnoringModifiers else { return super.keyDown(with: event) }
        if event.keyCode == 53 { controller?.escape(); return }
        if c == " " { controller?.toggleExplode(); return }
        if let d = c.first?.wholeNumberValue, d >= 1, d <= 9 { controller?.jump(toIndex: d - 1); return }
        super.keyDown(with: event)
    }
}

/// Logique de scène sans vue : caméra orbitale, lumières, animation. Partagée par l'ARView et le rendu hors-écran.
@MainActor
final class SceneDirector {
    static let backgroundColor = NSColor(srgbRed: 0.055, green: 0.064, blue: 0.075, alpha: 1)
    let rig: BoardRig
    private var input = SceneInput()
    private var lastTime = CACurrentMediaTime()
    private var clock: Float = 0
    private var frameCount = 0

    // Caméra
    let camera = PerspectiveCamera()
    let anchor = AnchorEntity(world: .zero)
    private var yaw: Float = 0.36, pitch: Float = 0.91, distance: Float = 2.55
    private var target = SIMD3<Float>(0, 0, 0.12)
    private var gYaw: Float = 0.36, gPitch: Float = 0.91, gDistance: Float = 2.55
    private var gTarget = SIMD3<Float>(0, 0, 0.12)
    static let overview = (yaw: Float(0.36), pitch: Float(0.91), distance: Float(2.55), target: SIMD3<Float>(0, 0, 0.12))

    private var diskScale: [Float] = [0, 0]
    private var diskTarget: [Float] = [0, 0]
    private var haloAlpha: Float = 0
    private var haloTarget: Float = 0
    private var haloColor: SIMD3<Float> = [0.2, 0.5, 1]

    init(gpuCoreCount: Int, model: Entity? = BoardRig.loadModel()) {
        rig = BoardRig(gpuCoreCount: gpuCoreCount, model: model)
        setupScene()
    }

    /// Éclairage IBL procédural, chargé de façon asynchrone puis appliqué par la vue ou le rendu hors-écran.
    private(set) var environment: EnvironmentResource?
    func installEnvironment() async {
        environment = await StudioLighting.makeEnvironment()
        if environment == nil { NSLog("IBL: création de l'environnement impossible") }
    }

    private func setupScene() {
        anchor.addChild(rig.root)
        camera.camera.fieldOfViewInDegrees = 34
        camera.camera.near = 0.02; camera.camera.far = 20
        anchor.addChild(camera)

        // Lumières : une clé directionnelle avec ombres, un contre-jour bleu, un point chaud près de la puce.
        let key = DirectionalLight()
        key.light.intensity = 1800
        key.light.color = NSColor(srgbRed: 1, green: 0.97, blue: 0.92, alpha: 1)
        key.shadow = DirectionalLightComponent.Shadow(maximumDistance: 3, depthBias: 1.5)
        key.look(at: .zero, from: [-0.6, 1.4, 0.8], relativeTo: nil)
        anchor.addChild(key)

        let rim = DirectionalLight()
        rim.light.intensity = 650
        rim.light.color = NSColor(srgbRed: 0.82, green: 0.89, blue: 1, alpha: 1)
        rim.look(at: .zero, from: [0.9, 0.5, -0.9], relativeTo: nil)
        anchor.addChild(rim)

        let fill = PointLight()
        fill.light.intensity = 300
        fill.light.color = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        fill.light.attenuationRadius = 3
        fill.position = [0.2, 0.9, 0.5]
        anchor.addChild(fill)

        // Sol discret : grille lumineuse qui s'estompe
        // The studio background keeps the silhouette legible without a luminous grid.
        applyCamera()
    }

    /// Sol : grille bleutée qui s'estompe dans la nuit.
    static func floorGrid() -> Entity {
        var mat = UnlitMaterial(color: .white)
        if let tex = ProceduralTextures.floor() {
            mat.color = .init(tint: .white, texture: .init(tex))
            mat.blending = .transparent(opacity: .init(scale: 0.30, texture: .init(tex)))
        }
        let plane = ModelEntity(mesh: .generatePlane(width: 3.4, depth: 3.4), materials: [mat])
        plane.position = [0, -0.06, 0.04]
        return plane
    }

    // MARK: Caméra

    private func applyCamera(immediate: Bool = false) {
        let p = target + distance * SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        camera.look(at: target, from: p, relativeTo: nil)
    }

    func orbit(dx: Float, dy: Float) {
        gYaw -= dx * 0.008
        gPitch = min(1.45, max(0.12, gPitch + dy * 0.008))
    }
    func pan(dx: Float, dy: Float) {
        let s = distance * 0.0016
        let right = SIMD3<Float>(cos(gYaw), 0, -sin(gYaw))
        let fwd = SIMD3<Float>(-sin(gYaw), 0, -cos(gYaw))
        gTarget += (-right * dx + fwd * dy * -1) * s
        gTarget.x = min(0.65, max(-0.65, gTarget.x)); gTarget.z = min(0.45, max(-0.35, gTarget.z)); gTarget.y = 0
    }
    func zoom(by f: Float) { gDistance = min(3.8, max(0.26, gDistance * (1 + f))) }

    func setCameraImmediate(yaw: Float, pitch: Float, distance: Float) {
        gYaw = yaw; gPitch = pitch; gDistance = distance
    }

    func snapCameraToGoal() { yaw = gYaw; pitch = gPitch; distance = gDistance; target = gTarget; applyCamera() }

    func resetCamera() {
        let o = Self.overview
        gYaw = o.yaw; gPitch = o.pitch; gDistance = o.distance; gTarget = o.target
    }

    func setView(_ preset: SceneCameraPreset) {
        if preset == .top { gYaw = 0; gPitch = 1.54 }
        else { gYaw = Self.overview.yaw; gPitch = Self.overview.pitch }
    }

    func focus(on id: ComponentID?) {
        guard let id, let f = rig.focus[id] else { resetCamera(); return }
        gTarget = f.center
        if input.exploded, id == .battery { gTarget += BoardRig.explodedBattery }
        gDistance = min(2.2, max(0.32, f.radius * 4.2 + 0.18))
        gPitch = 0.95
        gYaw = id == .battery ? 0.15 : 0.3
        if ComponentInfo.isInsideChip(id), rig.usesBlenderModel {
            gTarget = rig.siliconLayer.visualBounds(relativeTo: rig.root).center
            gDistance = 0.70
            gPitch = 1.05
            gYaw = 0.15
        }
    }

    // MARK: Entrée → cibles

    func apply(_ new: SceneInput) {
        let old = input
        input = new
        let r = rig
        r.setInspection(new.inspectChip)

        func level(_ id: ComponentID) -> HealthLevel { new.level[id] ?? .ok }
        func tint(_ id: ComponentID) -> SIMD3<Float> { Palette.rgb(level(id)) }

        func setTiles(_ tiles: [GlowPart], loads: [Float], id: ComponentID) {
            for (i, t) in tiles.enumerated() {
                let l = i < loads.count ? loads[i] : (loads.last ?? 0)
                t.target = l; t.targetColor = tint(id); t.pulse = level(id) != .ok && level(id) != .unavailable
            }
        }
        setTiles(r.perfTiles, loads: new.perfLoads, id: .performanceCores)
        setTiles(r.effTiles, loads: new.effLoads, id: .efficiencyCores)

        let n = Float(r.gpuTiles.count)
        for (i, t) in r.gpuTiles.enumerated() {
            let band = min(1, max(0, new.gpuUtilization * n - Float(i) + 0.35))
            t.target = max(new.gpuUtilization * 0.4, band) * (new.gpuUtilization > 0.01 ? 1 : 0)
            t.targetColor = tint(.gpu); t.pulse = level(.gpu) == .warning || level(.gpu) == .critical
        }
        r.aneTile?.target = new.aneLoad; r.aneTile?.targetColor = tint(.neuralEngine)

        // Chip (substrat) : léger éclat selon l'état
        for p in r.chipParts {
            p.target = level(.chip) == .ok ? 0.0 : 1.0
            p.targetColor = tint(.chip); p.pulse = level(.chip) != .ok && level(.chip) != .unavailable
        }

        // Mémoire : un segment par Go utilisé
        let segs = Float(r.memorySegments.count)
        for (i, s) in r.memorySegments.enumerated() {
            s.target = min(1, max(0, new.memoryUsed * segs - Float(i)))
            s.targetColor = tint(.memory); s.pulse = level(.memory) == .critical
        }
        // SSD : barres de remplissage
        diskTarget = [new.diskUsed * r.diskFullScale, new.diskUsed * r.diskFullScale]
        for (_, part) in r.diskBars {
            part.target = 0.55 + new.diskActivity * 0.45
            part.targetColor = tint(.ssd); part.pulse = level(.ssd) == .critical
        }
        for p in r.parts[.ssd] ?? [] where !r.diskBars.contains(where: { $0.part === p }) {
            p.target = new.diskActivity; p.targetColor = tint(.ssd)
        }
        // Batterie : cellules
        for (i, c) in r.batteryCells.enumerated() {
            c.target = new.hasBattery ? min(1, max(0, new.batteryCharge * 6 - Float(i))) : 0
            let low: HealthLevel = new.batteryCharge < 0.10 ? .critical : (new.batteryCharge < 0.20 ? .warning : level(.battery))
            c.targetColor = Palette.rgb(low == .ok && new.batteryCharging ? .ok : low)
            c.pulse = (new.batteryCharging && i == Int(new.batteryCharge * 6)) || low == .critical
        }
        // Wi-Fi
        for (i, b) in r.wifiBars.enumerated() {
            let lit = i < 3 ? (i < new.signalBars ? 1 : 0.0) : 1.0
            b.target = Float(lit) * (0.45 + new.netActivity * 0.55)
            b.targetColor = tint(.wireless)
        }
        // Ports
        for (i, p) in r.portParts.enumerated() {
            p.target = new.onAC && i == 0 ? 0.9 : (new.onAC ? 0.18 : 0.04)
            p.targetColor = new.onAC ? Palette.accent : tint(.power)
        }

        // Halo thermique
        let t = min(1, max(0, (new.chipTempC - 38) / 50))
        haloTarget = min(0.85, t * 0.7 + Float(new.thermalPressure) * 0.18)
        haloColor = t < 0.5 ? mix([0.25, 0.55, 1.0], [1.0, 0.7, 0.2], t * 2) : mix([1.0, 0.7, 0.2], [1.0, 0.2, 0.15], (t - 0.5) * 2)

        // Flux
        r.flows["memL"]?.activity = new.memoryActivity;  r.flows["memL"]?.speed = 0.25 + new.memoryActivity * 0.6
        r.flows["memR"]?.activity = new.memoryActivity;  r.flows["memR"]?.speed = 0.25 + new.memoryActivity * 0.6
        r.flows["power"]?.activity = new.hasBattery ? max(new.batteryDraw, new.onAC ? 0.25 : 0.0) : 0
        r.flows["power"]?.speed = 0.18 + new.batteryDraw * 0.4
        r.flows["ssd"]?.activity = new.diskActivity;     r.flows["ssd"]?.speed = 0.3 + new.diskActivity * 0.5
        r.flows["net"]?.activity = new.netActivity;      r.flows["net"]?.speed = 0.3 + new.netActivity * 0.5
        r.flows["power"]?.setColor(new.batteryCharging || new.onAC ? [0.3, 0.9, 0.6] : [1.0, 0.72, 0.25])

        // Survol / sélection
        for (id, parts) in r.parts {
            let b: Float = (new.selection == id ? 0.5 : 0) + (new.hovered == id ? 0.7 : 0)
            for p in parts { p.boost = b }
        }
        for (id, o) in r.outlines { o.isEnabled = new.selection == id || new.hovered == id }

        let navigationChanged = old.selection != new.selection || old.selectionRevision != new.selectionRevision || old.exploded != new.exploded
        if navigationChanged { focus(on: new.selection) }
        if new.exploded && new.selection == nil && navigationChanged {
            gDistance = 3.1; gPitch = 0.65; gTarget.y = -0.12
        }
    }


    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> { a + (b - a) * min(1, max(0, t)) }

    // MARK: Boucle d'image

    func frame(dt: Float) {
        let dt = min(dt, 0.1)
        clock += dt
        let k: Float = input.reduceMotion ? 1 : 1 - exp(-dt * 8)
        yaw += (gYaw - yaw) * k; pitch += (gPitch - pitch) * k
        distance += (gDistance - distance) * k; target += (gTarget - target) * k
        // Layer motion uses the same clock in the app and in offline validation.
        let layerK: Float = input.reduceMotion ? 1 : 1 - exp(-dt * 6)
        let batteryGoal = input.exploded ? BoardRig.explodedBattery : .zero
        let plateGoal = input.exploded ? BoardRig.explodedPlate : .zero
        let lidGoal: Float = input.exploded ? BoardRig.explodedLid : 0
        rig.batteryLayer.position += (batteryGoal - rig.batteryLayer.position) * layerK
        rig.bottomPlate.position += (plateGoal - rig.bottomPlate.position) * layerK
        rig.lidLayer.position.y += (lidGoal - rig.lidLayer.position.y) * layerK
        applyCamera()

        for parts in rig.parts.values { for p in parts { p.step(dt: dt, time: clock, reduceMotion: input.reduceMotion) } }
        for (i, d) in rig.diskBars.enumerated() {
            diskScale[i] += (diskTarget[i] - diskScale[i]) * k
            d.pivot.scale.x = max(0.004, diskScale[i])
        }
        for f in rig.flows.values { f.step(dt: dt, enabled: input.inspectChip && input.particles && !input.reduceMotion) }

        // Halo thermique
        haloAlpha += (haloTarget - haloAlpha) * min(1, dt * 3)
        var m = UnlitMaterial(color: .white)
        if let tex = haloTexture {
            m.color = .init(tint: Palette.ns(haloColor, alpha: CGFloat(haloAlpha)), texture: .init(tex))
            m.blending = .transparent(opacity: .init(scale: 1, texture: .init(tex)))
        }
        rig.halo.model?.materials = [m]
        let pulse = input.reduceMotion ? 1 : 1 + 0.04 * sin(clock * 1.4)
        rig.halo.scale = [0.6 * pulse, 1, 0.6 * pulse]
        rig.halo.isEnabled = !rig.usesBlenderModel && haloAlpha > 0.01
    }

    private lazy var haloTexture: TextureResource? = BoardRig.radialGradientTexture()
}

private extension SIMD3 where Scalar == Float {
    func with(y: Float) -> SIMD3<Float> { SIMD3(x, y, z) }
}


/// Vue à l'écran : ARView, picking souris, survol, bloom.
@MainActor
final class SceneController {
    let view: SiliciumARView
    let director: SceneDirector
    let bloom = BloomProcessor()
    private var updateSub: (any Cancellable)?
    private var frameCount = 0
    private var renderInstalled = false

    nonisolated(unsafe) static weak var current: SceneController?

    var onHover: ((ComponentID?, CGPoint) -> Void)?
    var onSelect: ((ComponentID?) -> Void)?
    var onToggleExplode: (() -> Void)?
    var onMarkers: (([SceneMarker]) -> Void)?
    private var sceneInput = SceneInput()
    private var hoverCandidate: ComponentID?
    private var hoverTask: Task<Void, Never>?

    init(gpuCoreCount: Int) {
        view = SiliciumARView(frame: NSRect(x: 0, y: 0, width: 900, height: 640))
        director = SceneDirector(gpuCoreCount: gpuCoreCount)
        view.controller = self
        Self.current = self
        view.environment.background = .color(SceneDirector.backgroundColor)
        view.scene.addAnchor(director.anchor)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await director.installEnvironment()
            if let env = director.environment {
                view.environment.lighting.resource = env
                view.environment.lighting.intensityExponent = StudioLighting.intensityExponent
            }
        }
        updateSub = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] e in
            MainActor.assumeIsolated { self?.tick(Float(e.deltaTime)) }
        }
    }

    private func tick(_ dt: Float) {
        director.frame(dt: dt)
        frameCount += 1
        if frameCount % 3 == 0 { projectMarkers() }
        // Le moteur de rendu doit être prêt avant d'installer les callbacks (sinon trap dans RealityKit).
        if frameCount == 20 { DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.installRenderCallbacksIfNeeded() } } }
    }

    func installRenderCallbacksIfNeeded() {
        guard !renderInstalled else { return }
        renderInstalled = true
        view.renderCallbacks = Self.makeCallbacks(bloom)
    }

    /// Fermetures non isolées : RealityKit les appelle depuis son thread de rendu.
    nonisolated static func makeCallbacks(_ bloom: BloomProcessor) -> ARView.RenderCallbacks {
        var cb = ARView.RenderCallbacks()
        cb.prepareWithDevice = { @Sendable device in bloom.prepare(device) }
        cb.postProcess = { @Sendable ctx in bloom.encode(ctx) }
        return cb
    }

    var rig: BoardRig { director.rig }
    func apply(_ i: SceneInput) { sceneInput = i; director.apply(i) }
    func setBloom(_ on: Bool) { bloom.enabled = on }
    func orbit(dx: Float, dy: Float) { director.orbit(dx: dx, dy: dy) }
    func pan(dx: Float, dy: Float) { director.pan(dx: dx, dy: dy) }
    func zoom(by f: Float) { director.zoom(by: f) }
    func resetCamera() { director.resetCamera() }
    func setCameraImmediate(yaw: Float, pitch: Float, distance: Float) { director.setCameraImmediate(yaw: yaw, pitch: pitch, distance: distance) }

    func setView(_ preset: SceneCameraPreset) { director.setView(preset) }

    private func projectMarkers() {
        let ids: [ComponentID]
        if sceneInput.inspectChip {
            ids = [.performanceCores, .efficiencyCores, .gpu, .neuralEngine]
        } else if let selection = sceneInput.selection {
            ids = [selection]
        } else {
            ids = [.chip, .memory, .ssd, .battery, .wireless, .power]
        }
        let markers = ids.compactMap { id -> SceneMarker? in
            guard let world = rig.markerPosition(for: id), let p = view.project(world) else { return nil }
            return SceneMarker(id: id, point: CGPoint(x: p.x, y: view.bounds.height - p.y))
        }
        onMarkers?(markers)
    }

    // MARK: Picking

    private func component(at p: CGPoint) -> ComponentID? {
        var e: Entity? = view.entity(at: p)
        while let x = e {
            if let tag = x.components[ComponentTag.self] { return tag.id }
            e = x.parent
        }
        return nil
    }

    func pointerMoved(_ p: CGPoint) {
        let c = component(at: p)
        // Survol : 150 ms de stabilité avant d'afficher la carte.
        if c != hoverCandidate {
            hoverCandidate = c
            hoverTask?.cancel()
            if c == nil { onHover?(nil, p); return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                self.onHover?(self.hoverCandidate, p)
            }
        } else if c != nil {
            onHover?(c, p)
        }
    }
    func pointerLeft() { hoverCandidate = nil; hoverTask?.cancel(); onHover?(nil, .zero) }
    func clicked(_ p: CGPoint) { onSelect?(component(at: p)) }
    func escape() { onSelect?(nil); director.resetCamera() }
    func toggleExplode() { onToggleExplode?() }
    func jump(toIndex i: Int) {
        let all = ComponentID.allCases
        if i < all.count { onSelect?(all[i]) }
    }

    func snapshotImage(_ completion: @escaping @Sendable (NSImage?) -> Void) {
        view.snapshot(saveToHDR: false) { image in completion(image) }
    }

    func verifyPicking() throws -> String {
        struct Miss: Error { let detail: String }
        let names: [(ComponentID, String)] = [
            (.chip, "PART__chip__die"), (.memory, "PART__memory__package0"),
            (.ssd, "PART__ssd__nand0"), (.battery, "PART__battery__pouch0"),
            (.wireless, "PART__wireless__module"), (.power, "PART__power__port0"),
            (.performanceCores, "PART__performanceCores__0"), (.efficiencyCores, "PART__efficiencyCores__0"),
            (.gpu, "PART__gpu__0"), (.neuralEngine, "PART__neuralEngine__0")
        ]
        let tested = names.filter { item in
            if sceneInput.inspectChip { return ComponentInfo.isInsideChip(item.0) }
            if let selection = sceneInput.selection { return item.0 == selection }
            return !ComponentInfo.isInsideChip(item.0)
        }
        for (id, name) in tested {
            guard let entity = rig.root.findEntity(named: name),
                  let point = view.project(entity.visualBounds(relativeTo: nil).center),
                  component(at: point) == id else { throw Miss(detail: "Picking failed for \(id)") }
        }
        return "PICKING_OK: \(tested.count) visible components respond to projected clicks."
    }
}

/// Aides de diagnostic pour la CI et les captures d'écran.
@MainActor
public enum DebugHooks {
    public static func verifyPicking() throws -> String {
        guard let controller = SceneController.current else { return "No active scene" }
        return try controller.verifyPicking()
    }
    public static func validateModel() throws -> String {
        struct Invalid: Error { let reason: String }
        guard let model = BoardRig.loadModel() else { throw Invalid(reason: "Missing or unreadable USDZ") }
        let rig = BoardRig(gpuCoreCount: 8, model: model)
        for layer in [rig.boardLayer, rig.batteryLayer, rig.bottomPlate, rig.lidLayer, rig.siliconLayer] {
            let up = layer.transformMatrix(relativeTo: rig.root).columns.1
            guard abs(up.y - 1) < 0.001, abs(up.z) < 0.001 else { throw Invalid(reason: "Layer axes are not Y-up") }
        }
        guard rig.usesBlenderModel else { throw Invalid(reason: "Unexpected fallback") }
        for id in ComponentID.allCases {
            guard let f = rig.focus[id], f.radius > 0, f.radius < 1,
                  f.center.x.isFinite, f.center.y.isFinite, f.center.z.isFinite,
                  rig.outlines[id] != nil else { throw Invalid(reason: "Missing bounds: \(id)") }
        }
        guard rig.perfTiles.count == 4, rig.effTiles.count == 6, rig.gpuTiles.count == 8, rig.aneTile != nil else {
            throw Invalid(reason: "Schematic units missing")
        }
        guard !rig.siliconLayer.isEnabled, rig.lidLayer.isEnabled else { throw Invalid(reason: "Incorrect physical mode") }
        rig.setInspection(true)
        guard rig.siliconLayer.isEnabled, !rig.lidLayer.isEnabled else { throw Invalid(reason: "Incorrect inspection mode") }
        rig.setInspection(false)
        return "MODEL_OK: 10 selectable components, 19 schematic units, physical/inspection visibility verified."
    }

    /// Capture native controls and the actual Metal scene without screen-recording access.
    public static func saveWindowSnapshot(to path: String, model: AppModel, completion: @escaping @MainActor () -> Void) {
        guard let controller = SceneController.current else { completion(); return }
        controller.snapshotImage { scene in
            Task { @MainActor in
                guard let scene else { completion(); return }
                model.reviewSceneImage = scene
                try? await Task.sleep(for: .milliseconds(400))
                guard let content = controller.view.window?.contentView,
                      let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { completion(); return }
                content.cacheDisplay(in: content.bounds, to: bitmap)
                let result = NSImage(size: content.bounds.size)
                result.lockFocus()
                bitmap.draw(in: content.bounds)
                result.unlockFocus()
                if let data = result.tiffRepresentation, let rep = NSBitmapImageRep(data: data) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                }
                model.reviewSceneImage = nil
                completion()
            }
        }
    }

    /// Enregistre le rendu 3D (PNG) du dernier `SceneController` créé.
    public static func renderOffline(to path: String, yaw: Float?, pitch: Float?, distance: Float?, exploded: Bool, selection: ComponentID?, hovered: ComponentID? = nil, width: Int = 1800, height: Int = 1100) async {
        var o = OfflineRender.Options()
        o.yaw = yaw; o.pitch = pitch; o.distance = distance; o.exploded = exploded; o.selection = selection; o.hovered = hovered
        o.width = width; o.height = height
        do { try await OfflineRender.render(to: path, options: o) } catch { NSLog("renderOffline: \(error)") }
    }
    public static func setCamera(yaw: Float, pitch: Float, distance: Float) { SceneController.current?.setCameraImmediate(yaw: yaw, pitch: pitch, distance: distance) }
    public static func saveSceneSnapshot(to path: String, completion: @escaping @MainActor () -> Void) {
        guard let c = SceneController.current else { completion(); return }
        c.snapshotImage { image in
            if let tiff = image?.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            Task { @MainActor in completion() }
        }
    }
}
