import Foundation
import SiliciumShared
import CSMC

/// Températures via SMC. Les clés changent à chaque génération de puce : on énumère les
/// clés `T*` de type flottant au premier lancement et on les groupe par préfixe.
public final class TemperatureSampler: Sampler {
    public typealias Reading = TemperatureReading?

    private var conn: UInt32 = 0
    private var groups: [String: [String]] = [:]   // « perf », « eff », « gpu », « soc », « bat », « ssd » → clés
    private var discovered = false
    public private(set) var discoveredKeys: [String: String] = [:]   // clé → type

    public init() { conn = csmc_open() }
    deinit { csmc_close(conn) }

    public var isAvailable: Bool { conn != 0 }

    private func read(_ key: String) -> Double? {
        var type = [CChar](repeating: 0, count: 5)
        var bytes = [UInt8](repeating: 0, count: 32)
        let k = Array(key.utf8CString.prefix(4))
        let n = k.withUnsafeBufferPointer { csmc_read_key(conn, $0.baseAddress, &type, &bytes) }
        guard n > 0 else { return nil }
        let t = String(cString: type)
        switch t {
        case "flt " where n >= 4:
            let raw = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: raw))
        case "sp78" where n >= 2:
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default: return nil
        }
    }

    private func discover() {
        discovered = true
        guard conn != 0 else { return }
        let count = csmc_key_count(conn)
        guard count > 0 else { return }
        var out = [CChar](repeating: 0, count: 5)
        for i in 0..<UInt32(count) {
            guard csmc_key_at_index(conn, i, &out) else { continue }
            let key = String(cString: out)
            guard key.hasPrefix("T"), key.count == 4 else { continue }
            guard let v = read(key), v > 5, v < 130 else { continue }
            discoveredKeys[key] = "temp"
            let group: String
            switch key.prefix(2) {
            case "Tp", "TP": group = "perf"
            case "Te", "TE": group = "eff"
            case "Tg", "TG": group = "gpu"
            case "TB": group = "bat"
            case "TN", "Ts": group = "ssd"
            case "Tf", "TC", "Tc": group = "soc"
            default: group = "soc"
            }
            groups[group, default: []].append(key)
        }
    }

    private func avg(_ keys: [String]?) -> Double? {
        guard let keys else { return nil }
        let vals = keys.compactMap { read($0) }.filter { $0 > 5 && $0 < 130 }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }

    private func peak(_ keys: [String]?) -> Double? {
        guard let keys else { return nil }
        return keys.compactMap { read($0) }.filter { $0 > 5 && $0 < 130 }.max()
    }

    public func sample() throws -> TemperatureReading? {
        guard conn != 0 else { return nil }
        if !discovered { discover() }
        guard !groups.isEmpty else { return nil }
        let t = TemperatureReading(
            perfCoresC: peak(groups["perf"]), effCoresC: peak(groups["eff"]), gpuC: avg(groups["gpu"]),
            socC: avg(groups["soc"]), batteryC: avg(groups["bat"]), ssdC: avg(groups["ssd"]))
        return t == TemperatureReading() ? nil : t
    }

    /// Liste brute (clé = valeur) pour la cartographie des capteurs.
    public func dump() -> [(String, Double)] {
        if !discovered { discover() }
        return discoveredKeys.keys.sorted().compactMap { k in read(k).map { (k, $0) } }
    }
}
