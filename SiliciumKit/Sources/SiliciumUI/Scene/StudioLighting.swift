import RealityKit
import AppKit
import CoreGraphics

/// Éclairage « studio » procédural (IBL) : fond bleu nuit et boîtes à lumière,
/// pour donner de vrais reflets aux métaux et au silicium sans fichier HDR externe.
@MainActor
enum StudioLighting {
    static let intensityExponent: Float = 1.1
    static func makeEnvironment() async -> EnvironmentResource? {
        guard let img = makeEquirect() else { return nil }
        do { return try await EnvironmentResource(equirectangular: img, withName: "silicium-studio") } catch { NSLog("IBL erreur: \(error)"); return nil }
    }

    static func makeEquirect(width w: Int = 1024, height h: Int = 512) -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
        // Dégradé vertical (haut du CGContext = zénith)
        let sky = CGGradient(colorsSpace: cs, colors: [c(0.36, 0.38, 0.40), c(0.18, 0.19, 0.21), c(0.08, 0.09, 0.10)] as CFArray, locations: [0, 0.5, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: CGFloat(h)), end: .zero, options: [])

        func softbox(_ x: CGFloat, _ y: CGFloat, _ bw: CGFloat, _ bh: CGFloat, _ color: CGColor, falloff: CGFloat = 0.5) {
            // halo doux autour d'un rectangle lumineux
            let rect = CGRect(x: x - bw / 2, y: y - bh / 2, width: bw, height: bh)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: min(bw, bh) * falloff, color: color)
            ctx.setFillColor(color)
            ctx.fill(rect)
            ctx.restoreGState()
        }
        let W = CGFloat(w), H = CGFloat(h)
        softbox(W * 0.30, H * 0.78, W * 0.22, H * 0.20, c(1, 1, 1))                 // clé : grande boîte haute, côté gauche
        softbox(W * 0.62, H * 0.62, W * 0.05, H * 0.34, c(0.9, 0.95, 1))           // bande froide
        softbox(W * 0.90, H * 0.55, W * 0.04, H * 0.28, c(1.0, 0.94, 0.84), falloff: 0.7)   // appoint chaud
        softbox(W * 0.12, H * 0.45, W * 0.03, H * 0.22, c(0.85, 0.9, 1.0))          // liseré bleu
        softbox(W * 0.50, H * 0.93, W * 0.30, H * 0.07, c(0.9, 0.95, 1))            // plafond
        return ctx.makeImage()
    }
}
