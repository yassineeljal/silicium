import RealityKit
import AppKit
import CoreGraphics

/// Textures générées en code (CoreGraphics) : aucun fichier externe, rendu identique partout.
@MainActor
enum ProceduralTextures {
    /// Générateur pseudo-aléatoire déterministe (même image à chaque lancement).
    struct RNG {
        var s: UInt64
        mutating func next() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double((s >> 33) & 0xFFFFFF) / Double(0x1000000)
        }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
        mutating func int(_ a: Int, _ b: Int) -> Int { a + Int(next() * Double(b - a + 1)) }
    }

    private static func context(_ w: Int, _ h: Int) -> CGContext {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.setLineCap(.round); c.setLineJoin(.round)
        return c
    }

    private static func resource(_ ctx: CGContext, semantic: TextureResource.Semantic = .color) -> TextureResource? {
        guard let img = ctx.makeImage() else { return nil }
        return try? TextureResource(image: img, options: .init(semantic: semantic))
    }

    // MARK: Carte (PCB)

    /// `u` = x / 1.0 m, `v` = (z + 0.30) / 0.46 m — même orientation que la maquette.
    static func pcb(width w: Int = 2048, height h: Int = 942) -> TextureResource? {
        let c = context(w, h)
        var rng = RNG(s: 42)
        // Fond : bleu-noir avec dégradé léger
        let bg = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            CGColor(red: 0.050, green: 0.064, blue: 0.095, alpha: 1), CGColor(red: 0.030, green: 0.038, blue: 0.060, alpha: 1)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(bg, start: .zero, end: CGPoint(x: CGFloat(w), y: CGFloat(h)), options: [])
        // Grain
        for _ in 0..<5000 {
            let x = rng.range(0, Double(w)), y = rng.range(0, Double(h)), a = rng.range(0.02, 0.06)
            c.setFillColor(CGColor(red: 0.6, green: 0.7, blue: 1, alpha: a))
            c.fill(CGRect(x: x, y: y, width: 2, height: 2))
        }
        let trace = CGColor(red: 0.16, green: 0.25, blue: 0.40, alpha: 0.85)
        let traceHi = CGColor(red: 0.28, green: 0.45, blue: 0.70, alpha: 0.75)
        // Pistes aléatoires (marche Manhattan avec biseaux 45°)
        for i in 0..<260 {
            var x = Double(rng.int(0, w / 10) * 10), y = Double(rng.int(0, h / 10) * 10)
            c.setStrokeColor(i % 9 == 0 ? traceHi : trace); c.setLineWidth(i % 7 == 0 ? 4 : 2.5)
            c.move(to: CGPoint(x: x, y: y))
            var horizontal = rng.next() > 0.5
            for _ in 0..<rng.int(3, 8) {
                let len = rng.range(40, 260) * (rng.next() > 0.5 ? 1 : -1)
                if horizontal { x += len } else { y += len }
                if rng.next() > 0.7 { x += (horizontal ? 0 : 30); y += (horizontal ? 30 : 0) }   // biseau
                c.addLine(to: CGPoint(x: x, y: y)); horizontal.toggle()
            }
            c.strokePath()
            c.setFillColor(traceHi); c.fillEllipse(in: CGRect(x: x - 6, y: y - 6, width: 12, height: 12))
            c.setFillColor(CGColor(red: 0.02, green: 0.03, blue: 0.05, alpha: 1)); c.fillEllipse(in: CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5))
        }
        // Bus parallèles entre mémoire et puce
        func bus(u0: Double, u1: Double, v: Double, lines: Int, spacing: Double) {
            for k in 0..<lines {
                let y = (v * Double(h)) + Double(k - lines / 2) * spacing
                let jog = rng.range(-12, 12)
                c.setStrokeColor(traceHi); c.setLineWidth(2.6)
                c.move(to: CGPoint(x: u0 * Double(w), y: y))
                c.addLine(to: CGPoint(x: (u0 + (u1 - u0) * 0.45) * Double(w), y: y))
                c.addLine(to: CGPoint(x: (u0 + (u1 - u0) * 0.55) * Double(w), y: y + jog))
                c.addLine(to: CGPoint(x: u1 * Double(w), y: y + jog)); c.strokePath()
            }
        }
        bus(u0: 0.22, u1: 0.33, v: 0.43, lines: 22, spacing: 7)
        bus(u0: 0.51, u1: 0.63, v: 0.43, lines: 22, spacing: 7)
        // Sérigraphie : contours des composants (u,v,w,h normalisés)
        c.setStrokeColor(CGColor(red: 0.8, green: 0.9, blue: 1, alpha: 0.20)); c.setLineWidth(2)
        let marks: [(Double, Double, Double, Double)] = [(0.145, 0.43, 0.15, 0.55), (0.695, 0.43, 0.15, 0.55), (0.42, 0.43, 0.33, 0.70),
                                                          (0.27, 0.80, 0.34, 0.24), (0.57, 0.80, 0.34, 0.24), (0.83, 0.10, 0.16, 0.18)]
        for m in marks {
            let r = CGRect(x: (m.0 - m.2 / 2) * Double(w), y: (m.1 - m.3 / 2) * Double(h), width: m.2 * Double(w), height: m.3 * Double(h))
            c.stroke(r.insetBy(dx: -8, dy: -8))
        }
        return resource(c)
    }

    // MARK: Motifs émissifs (le teint de couleur est appliqué par le matériau)

    enum Pattern { case cells, fine, stripes, weave, dots }

    static func emissive(_ pattern: Pattern, size: Int = 256) -> TextureResource? {
        let c = context(size, size)
        var rng = RNG(s: UInt64(size) &+ 7)
        let S = Double(size)
        c.setFillColor(CGColor(gray: 0.30, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: S, height: S))
        switch pattern {
        case .cells:
            let n = 14, cell = S / Double(n)
            for i in 0..<n { for j in 0..<n {
                let v = rng.range(0.55, 1.0)
                c.setFillColor(CGColor(gray: v, alpha: 1))
                c.fill(CGRect(x: Double(i) * cell + 2, y: Double(j) * cell + 2, width: cell - 4, height: cell - 4))
            } }
            c.setFillColor(CGColor(gray: 1, alpha: 1))
            for k in stride(from: 0, to: n, by: 4) { c.fill(CGRect(x: 0, y: Double(k) * cell - 1, width: S, height: 3)) }
        case .fine:
            let n = 32, cell = S / Double(n)
            for i in 0..<n { for j in 0..<n {
                let v = rng.range(0.45, 1.0) * (j % 8 == 0 ? 1.0 : 0.85)
                c.setFillColor(CGColor(gray: v, alpha: 1))
                c.fill(CGRect(x: Double(i) * cell + 0.8, y: Double(j) * cell + 0.8, width: cell - 1.6, height: cell - 1.6))
            } }
        case .stripes:
            let n = 18, cell = S / Double(n)
            for j in 0..<n {
                c.setFillColor(CGColor(gray: rng.range(0.7, 1.0), alpha: 1))
                c.fill(CGRect(x: 6, y: Double(j) * cell + 2.5, width: S - 12, height: cell - 5))
            }
        case .weave:
            let n = 22, cell = S / Double(n)
            for i in 0..<n { for j in 0..<n {
                c.setFillColor(CGColor(gray: (i + j) % 2 == 0 ? 1.0 : 0.86, alpha: 1))
                c.fill(CGRect(x: Double(i) * cell + 1, y: Double(j) * cell + 1, width: cell - 2, height: cell - 2))
            } }
        case .dots:
            let n = 12, cell = S / Double(n)
            for i in 0..<n { for j in 0..<n {
                c.setFillColor(CGColor(gray: rng.range(0.6, 1.0), alpha: 1))
                c.fillEllipse(in: CGRect(x: Double(i) * cell + 4, y: Double(j) * cell + 4, width: cell - 8, height: cell - 8))
            } }
        }
        return resource(c)
    }

    // MARK: Silicium (die)

    /// Plan de masse d'une puce : lignes de cellules standard, blocs, bus colorés.
    static func die(size: Int = 1024) -> TextureResource? {
        let c = context(size, size)
        var rng = RNG(s: 99)
        let S = Double(size)
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            CGColor(red: 0.04, green: 0.06, blue: 0.13, alpha: 1), CGColor(red: 0.02, green: 0.03, blue: 0.07, alpha: 1)] as CFArray, locations: [0, 1])!
        c.drawLinearGradient(g, start: .zero, end: CGPoint(x: S, y: S), options: [])
        // Lignes de cellules
        c.setLineWidth(1)
        for y in stride(from: 0.0, to: S, by: 6) {
            c.setStrokeColor(CGColor(red: 0.2, green: 0.35, blue: 0.7, alpha: rng.range(0.05, 0.16)))
            c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: S, y: y)); c.strokePath()
        }
        // Blocs aléatoires iridescents
        let hues: [(CGFloat, CGFloat, CGFloat)] = [(0.2, 0.5, 0.9), (0.5, 0.3, 0.9), (0.1, 0.8, 0.7), (0.8, 0.5, 0.3)]
        for _ in 0..<70 {
            let h = hues[rng.int(0, hues.count - 1)]
            let r = CGRect(x: rng.range(0, S - 90), y: rng.range(0, S - 90), width: rng.range(20, 90), height: rng.range(10, 60))
            c.setFillColor(CGColor(red: h.0, green: h.1, blue: h.2, alpha: rng.range(0.04, 0.14))); c.fill(r)
            c.setStrokeColor(CGColor(red: h.0, green: h.1, blue: h.2, alpha: 0.25)); c.stroke(r)
        }
        // Bus
        c.setStrokeColor(CGColor(red: 0.5, green: 0.75, blue: 1, alpha: 0.25)); c.setLineWidth(1.5)
        for _ in 0..<40 {
            let y = rng.range(0, S); c.move(to: CGPoint(x: rng.range(0, S / 2), y: y)); c.addLine(to: CGPoint(x: rng.range(S / 2, S), y: y)); c.strokePath()
        }
        return resource(c)
    }

    // MARK: Sol

    /// Grille qui s'estompe avec la distance + halo lumineux sous la maquette.
    static func floor(size: Int = 1024) -> TextureResource? {
        let c = context(size, size)
        let S = CGFloat(size)
        c.setStrokeColor(CGColor(red: 0.30, green: 0.50, blue: 0.95, alpha: 0.5)); c.setLineWidth(1.0)
        let n = 48
        for i in 0...n {
            let t = S * CGFloat(i) / CGFloat(n)
            c.move(to: CGPoint(x: t, y: 0)); c.addLine(to: CGPoint(x: t, y: S))
            c.move(to: CGPoint(x: 0, y: t)); c.addLine(to: CGPoint(x: S, y: t))
        }
        c.strokePath()
        // Masque radial : on efface vers les bords
        c.setBlendMode(.destinationIn)
        let mask = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
            CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 0.45, 1])!
        c.drawRadialGradient(mask, startCenter: CGPoint(x: S / 2, y: S / 2), startRadius: 0, endCenter: CGPoint(x: S / 2, y: S / 2), endRadius: S / 2, options: [])
        c.setBlendMode(.normal)
        return resource(c)
    }
}
