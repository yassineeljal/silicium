import Foundation

public enum Fmt {
    public static func percent(_ f: Double, digits: Int = 0) -> String {
        let p = max(0, f) * 100
        return digits == 0 ? "\(Int(p.rounded())) %" : String(format: "%.\(digits)f %%", p).replacingOccurrences(of: ".", with: ",")
    }
    public static func bytes(_ b: UInt64) -> String { bytes(Double(b)) }
    public static func bytes(_ b: Double) -> String {
        let units = ["o", "Ko", "Mo", "Go", "To"]
        var v = max(0, b); var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        let s = i >= 3 ? String(format: "%.1f", v) : (i == 0 ? String(format: "%.0f", v) : String(format: "%.0f", v))
        return "\(s.replacingOccurrences(of: ".", with: ",")) \(units[i])"
    }
    public static func rate(_ bps: Double) -> String { bytes(bps) + "/s" }
    public static func watts(_ w: Double) -> String { String(format: "%.1f W", w).replacingOccurrences(of: ".", with: ",") }
    public static func celsius(_ c: Double) -> String { "\(Int(c.rounded())) °C" }
    public static func ghz(_ mhz: Double) -> String { String(format: "%.2f GHz", mhz / 1000).replacingOccurrences(of: ".", with: ",") }
}

public func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
