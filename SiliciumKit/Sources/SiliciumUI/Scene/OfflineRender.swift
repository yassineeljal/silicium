import RealityKit
import Metal
import AppKit
import SiliciumShared

/// Rendu hors-écran de la scène (sans fenêtre) : sert aux captures de vérification et aux tests visuels.
@MainActor
public enum OfflineRender {
    public struct Options: Sendable {
        public var width = 1800, height = 1100
        public var yaw: Float?, pitch: Float?, distance: Float?
        public var exploded = false
        public var selection: ComponentID?
        public var hovered: ComponentID?
        public var bloom = false
        public init() {}
    }

    /// Entrée plausible (charge moyenne, SSD/batterie en ambre) pour juger le design.
    static func sampleInput() -> SceneInput {
        var i = SceneInput()
        for c in ComponentID.allCases { i.level[c] = .ok; i.load[c] = 0.3 }
        i.level[.ssd] = .warning; i.level[.battery] = .ok
        i.perfLoads = [0.95, 0.7, 0.35, 0.1]
        i.effLoads = [0.5, 0.3, 0.2, 0.15, 0.1, 0.05]
        i.gpuUtilization = 0.55; i.aneLoad = 0.35
        i.memoryUsed = 0.73; i.memoryActivity = 0.7
        i.diskUsed = 0.9; i.diskActivity = 0.4
        i.batteryCharge = 0.6; i.batteryDraw = 0.5; i.hasBattery = true; i.onAC = true; i.batteryCharging = true
        i.netActivity = 0.5; i.signalBars = 3
        i.chipTempC = 62; i.thermalPressure = 0
        return i
    }

    static func render(to path: String, options o: Options = .init(), input: SceneInput? = nil) async throws {
        let director = SceneDirector(gpuCoreCount: 8)
        await director.installEnvironment()
        var inp = input ?? sampleInput()
        inp.exploded = o.exploded; inp.selection = o.selection; inp.hovered = o.hovered
        inp.inspectChip = o.selection.map(ComponentInfo.isInsideChip) ?? false
        director.apply(inp)
        if let y = o.yaw, let p = o.pitch, let d = o.distance { director.setCameraImmediate(yaw: y, pitch: p, distance: d) }
        if o.selection != nil { director.focus(on: o.selection) }
        for _ in 0..<150 { director.frame(dt: 1.0 / 30) }   // laisse les lissages converger
        director.snapCameraToGoal()

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try RealityRenderer()
        renderer.entities.append(director.anchor)
        renderer.activeCamera = director.camera
        if let env = director.environment { renderer.lighting.resource = env; renderer.lighting.intensityExponent = StudioLighting.intensityExponent }
        renderer.cameraSettings.colorBackground = .color(SceneDirector.backgroundColor.cgColor)
        renderer.cameraSettings.isToneMappingEnabled = true
        director.camera.camera.fieldOfViewInDegrees = 34

        // Match the display's sRGB transfer function; linear UNorm made exports too dark.
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: o.width, height: o.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        guard let color = device.makeTexture(descriptor: d) else { return }
        let out = try RealityRenderer.CameraOutput(.singleProjection(colorTexture: color))
        for _ in 0..<40 {
            try renderer.updateAndRender(deltaTime: 1.0 / 30, cameraOutput: out)
            try await Task.sleep(for: .milliseconds(100))
        }
        var final = color
        let bloomDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: o.width, height: o.height, mipmapped: false)
        bloomDescriptor.usage = [.shaderRead, .shaderWrite]
        if o.bloom, let queue = device.makeCommandQueue(), let cb = queue.makeCommandBuffer(), let dst = device.makeTexture(descriptor: bloomDescriptor) {
            let bloom = BloomProcessor(); bloom.prepare(device)
            bloom.encodeStandalone(device: device, commandBuffer: cb, source: color, target: dst)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                cb.addCompletedHandler { _ in c.resume() }
                cb.commit()
            }
            final = dst
        }
        try save(final, to: path, linear: o.bloom && final !== color)
    }

    private static func save(_ tex: MTLTexture, to path: String, linear: Bool) throws {
        let w = tex.width, h = tex.height, bpr = w * 4
        var bytes = [UInt8](repeating: 0, count: bpr * h)
        tex.getBytes(&bytes, bytesPerRow: bpr, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        // BGRA → RGBA
        for i in stride(from: 0, to: bytes.count, by: 4) { bytes.swapAt(i, i + 2) }
        if linear {
            for i in stride(from: 0, to: bytes.count, by: 4) {
                for channel in 0..<3 {
                    let value = Float(bytes[i + channel]) / 255
                    let srgb = value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
                    bytes[i + channel] = UInt8(clamping: Int((srgb * 255).rounded()))
                }
            }
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = bytes.withUnsafeMutableBytes { CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: bpr, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) }
        guard let img = ctx?.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: img)
        try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
