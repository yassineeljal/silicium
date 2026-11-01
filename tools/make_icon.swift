// Génère l'icône de Silicium : swift tools/make_icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit
import CoreGraphics

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let inset = s * 0.055
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = rect.width * 0.225
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
    let bg = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.06, green: 0.09, blue: 0.16, alpha: 1), CGColor(red: 0.01, green: 0.02, blue: 0.05, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: s / 2, y: s), end: CGPoint(x: s / 2, y: 0), options: [])
    // lueur centrale
    let glow = CGGradient(colorsSpace: cs, colors: [CGColor(red: 0.1, green: 0.9, blue: 0.6, alpha: 0.55), CGColor(red: 0.1, green: 0.9, blue: 0.6, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: s / 2, y: s / 2), startRadius: 0, endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s * 0.46, options: [])
    // broches
    ctx.setStrokeColor(CGColor(red: 0.55, green: 0.65, blue: 0.8, alpha: 0.9)); ctx.setLineWidth(s * 0.018); ctx.setLineCap(.round)
    let c = s / 2, half = s * 0.2
    for i in -2...2 {
        let o = CGFloat(i) * s * 0.075
        for (a, b) in [(CGPoint(x: c + o, y: c + half), CGPoint(x: c + o, y: c + half + s * 0.09)), (CGPoint(x: c + o, y: c - half), CGPoint(x: c + o, y: c - half - s * 0.09)),
                       (CGPoint(x: c + half, y: c + o), CGPoint(x: c + half + s * 0.09, y: c + o)), (CGPoint(x: c - half, y: c + o), CGPoint(x: c - half - s * 0.09, y: c + o))] {
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
        }
    }
    // boîtier
    let body = CGRect(x: c - half, y: c - half, width: half * 2, height: half * 2)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil))
    ctx.setFillColor(CGColor(red: 0.09, green: 0.12, blue: 0.19, alpha: 1)); ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil))
    ctx.setStrokeColor(CGColor(red: 0.7, green: 0.8, blue: 0.95, alpha: 0.9)); ctx.setLineWidth(s * 0.012); ctx.strokePath()
    // tuiles de cœurs (2×2 allumées + bande)
    let t = half * 0.62, gap = s * 0.014
    let colors: [CGColor] = [CGColor(red: 0.1, green: 0.95, blue: 0.62, alpha: 1), CGColor(red: 0.1, green: 0.95, blue: 0.62, alpha: 0.85), CGColor(red: 0.1, green: 0.95, blue: 0.62, alpha: 0.55), CGColor(red: 0.3, green: 0.6, blue: 1, alpha: 0.9)]
    for r in 0..<2 { for k in 0..<2 {
        let x = c - t - gap / 2 + CGFloat(k) * (t + gap), y = c - t - gap / 2 + CGFloat(r) * (t + gap)
        let tile = CGRect(x: x, y: y, width: t, height: t)
        ctx.addPath(CGPath(roundedRect: tile, cornerWidth: s * 0.014, cornerHeight: s * 0.014, transform: nil))
        ctx.setFillColor(colors[r * 2 + k]); ctx.fillPath()
    } }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
let sizes: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [String] = []
for (pt, sc) in sizes {
    let name = "icon_\(pt)x\(pt)\(sc == 2 ? "@2x" : "").png"
    try render(pt * sc).write(to: URL(fileURLWithPath: "\(dir)/\(name)"))
    images.append("{ \"filename\" : \"\(name)\", \"idiom\" : \"mac\", \"scale\" : \"\(sc)x\", \"size\" : \"\(pt)x\(pt)\" }")
}
try "{ \"images\" : [\(images.joined(separator: ",\n"))], \"info\" : { \"author\" : \"xcode\", \"version\" : 1 } }".write(toFile: "\(dir)/Contents.json", atomically: true, encoding: .utf8)
