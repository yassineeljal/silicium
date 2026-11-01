import Foundation
import SiliciumShared
import IOKit
import IOKit.ps

/// Batterie : `IOPowerSources` + `AppleSmartBattery` (cycles, capacité, température, ampérage).
public final class BatterySampler: Sampler {
    public typealias Reading = BatteryReading?
    public init() {}

    public func sample() throws -> BatteryReading? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }

        func num(_ k: String) -> Double? { (d[k] as? NSNumber)?.doubleValue }
        func bool(_ k: String) -> Bool { (d[k] as? NSNumber)?.boolValue ?? false }

        let percent = (num("CurrentCapacity") ?? 0) / 100   // sur Apple Silicon: pourcentage
        let rawMax = num("AppleRawMaxCapacity") ?? num("MaxCapacity")
        let design = num("DesignCapacity")
        var maxFraction: Double?
        if let rawMax, let design, design > 0 { maxFraction = min(1.2, rawMax / design) }

        var temp = num("Temperature")
        if let t = temp { temp = t / 100 }
        // Ampérage signé (mA) × tension (mV) → watts. Positif = charge.
        var watts: Double?
        if let amps = num("InstantAmperage"), let volt = num("Voltage") {
            let signed = amps > Double(Int64.max) / 2 ? amps - 18446744073709551616.0 : amps
            watts = signed * volt / 1_000_000
        }
        var adapter: Double?
        if let ad = d["AdapterDetails"] as? [String: Any] { adapter = (ad["Watts"] as? NSNumber)?.doubleValue }
        else if let w = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            adapter = (w[kIOPSPowerAdapterWattsKey] as? NSNumber)?.doubleValue
        }
        var remaining: Int?
        if let t = num("TimeRemaining"), t < 65535 { remaining = Int(t) }

        return BatteryReading(
            chargeFraction: clamp01(percent), isCharging: bool("IsCharging"),
            onACPower: bool("ExternalConnected"), cycleCount: Int(num("CycleCount") ?? 0),
            maxCapacityFraction: maxFraction, temperatureC: temp, watts: watts,
            adapterWatts: adapter, timeRemainingMinutes: remaining)
    }
}
