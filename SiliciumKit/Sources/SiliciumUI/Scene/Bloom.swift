import RealityKit
import Metal
import MetalPerformanceShaders

/// Post-traitement « bloom » : les surfaces émissives débordent en halo lumineux.
/// RealityKit n'en fournit pas ; on passe par `ARView.renderCallbacks.postProcess` + MPS.
final class BloomProcessor: @unchecked Sendable {
    private let lock = NSLock()
    private var _enabled = true
    var enabled: Bool { get { lock.withLock { _enabled } } set { lock.withLock { _enabled = newValue } } }

    private var device: MTLDevice?
    private var threshold: MPSImageThresholdToZero?
    private var blurTight: MPSImageGaussianBlur?
    private var blurWide: MPSImageGaussianBlur?
    private var add: MPSImageAdd?
    private var scratch: [MTLTexture] = []
    private var scratchKey = ""

    func prepare(_ device: MTLDevice) {
        self.device = device
        threshold = MPSImageThresholdToZero(device: device, thresholdValue: 0.85, linearGrayColorTransform: nil)
        blurTight = MPSImageGaussianBlur(device: device, sigma: 5)
        blurWide = MPSImageGaussianBlur(device: device, sigma: 20)
        add = MPSImageAdd(device: device)
    }

    private func textures(for source: MTLTexture, device: MTLDevice) -> [MTLTexture] {
        let key = "\(source.width)x\(source.height)-\(source.pixelFormat.rawValue)"
        if key == scratchKey, scratch.count == 4 { return scratch }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: source.pixelFormat, width: source.width, height: source.height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite, .renderTarget]
        d.storageMode = .private
        scratch = (0..<4).compactMap { _ in device.makeTexture(descriptor: d) }
        scratchKey = key
        return scratch
    }

    func encode(_ ctx: ARView.PostProcessContext) {
        let cb = ctx.commandBuffer
        let src = ctx.sourceColorTexture, dst = ctx.targetColorTexture
        guard enabled, let threshold, let blurTight, let blurWide, let add else { return copy(ctx) }
        let t = textures(for: src, device: ctx.device)
        guard t.count == 4 else { return copy(ctx) }
        threshold.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: t[0])
        blurTight.encode(commandBuffer: cb, sourceTexture: t[0], destinationTexture: t[1])
        blurWide.encode(commandBuffer: cb, sourceTexture: t[0], destinationTexture: t[2])
        add.primaryScale = 1; add.secondaryScale = 0.55
        add.encode(commandBuffer: cb, primaryTexture: src, secondaryTexture: t[1], destinationTexture: t[3])
        add.primaryScale = 1; add.secondaryScale = 0.8
        add.encode(commandBuffer: cb, primaryTexture: t[3], secondaryTexture: t[2], destinationTexture: dst)
    }

    /// Variante hors-écran (sans `PostProcessContext`).
    func encodeStandalone(device: MTLDevice, commandBuffer cb: MTLCommandBuffer, source src: MTLTexture, target dst: MTLTexture) {
        guard let threshold, let blurTight, let blurWide, let add else { return }
        let t = textures(for: src, device: device)
        guard t.count == 4 else { return }
        threshold.encode(commandBuffer: cb, sourceTexture: src, destinationTexture: t[0])
        blurTight.encode(commandBuffer: cb, sourceTexture: t[0], destinationTexture: t[1])
        blurWide.encode(commandBuffer: cb, sourceTexture: t[0], destinationTexture: t[2])
        add.primaryScale = 1; add.secondaryScale = 0.55
        add.encode(commandBuffer: cb, primaryTexture: src, secondaryTexture: t[1], destinationTexture: t[3])
        add.primaryScale = 1; add.secondaryScale = 0.8
        add.encode(commandBuffer: cb, primaryTexture: t[3], secondaryTexture: t[2], destinationTexture: dst)
    }

    private func copy(_ ctx: ARView.PostProcessContext) {
        guard let blit = ctx.commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: ctx.sourceColorTexture, to: ctx.targetColorTexture)
        blit.endEncoding()
    }
}
