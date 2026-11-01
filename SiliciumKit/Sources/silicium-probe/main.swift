import Foundation
import SiliciumShared
import SiliciumSensors
import SiliciumCore

// Outil de diagnostic / cartographie des capteurs.
//   silicium-probe            → 4 ticks du SensorHub en JSON lisible
//   silicium-probe channels   → canaux IOReport bruts
//   silicium-probe smc        → clés SMC de température
let args = CommandLine.arguments.dropFirst()
switch args.first {
case "channels":
    let p = PowerSampler()
    _ = p.debugChannels()
    try? await Task.sleep(for: .seconds(1))
    for l in p.debugChannels() { print(l) }
case "smc":
    let t = TemperatureSampler()
    for (k, v) in t.dump() { print(k, String(format: "%.1f", v)) }
default:
    let hub = SensorHub()
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    for i in 0..<4 {
        let s = await hub.tick()
        if i == 3 { print(String(decoding: try enc.encode(s), as: UTF8.self)) }
        try? await Task.sleep(for: .seconds(1))
    }
    print(await hub.availability())
}
