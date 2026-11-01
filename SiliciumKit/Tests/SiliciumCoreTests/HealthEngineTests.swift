import Testing
import Foundation
import SiliciumShared
@testable import SiliciumCore

private func baseSnapshot(at date: Date = .now) -> Snapshot {
    Snapshot(date: date,
             cpu: CPUReading(perfLoad: [0.1, 0.1, 0.1, 0.1], effLoad: Array(repeating: 0.1, count: 6)),
             gpu: GPUReading(utilization: 0.05, allocatedBytes: 0, inUseBytes: 0),
             power: PowerReading(cpuWatts: 1, gpuWatts: 0.1, aneWatts: 0, dramWatts: 0.2),
             memory: MemoryReading(totalBytes: 16 << 30, usedBytes: 8 << 30, appBytes: 5 << 30, wiredBytes: 2 << 30,
                                   compressedBytes: 1 << 30, cachedBytes: 2 << 30, swapUsedBytes: 0, pressure: .normal),
             disk: DiskReading(totalBytes: 500 << 30, freeBytes: 250 << 30, readBytesPerSec: 0, writeBytesPerSec: 0),
             battery: BatteryReading(chargeFraction: 0.8, isCharging: false, onACPower: false, cycleCount: 100,
                                     maxCapacityFraction: 0.95, temperatureC: 30, watts: -8),
             network: NetworkReading(downBytesPerSec: 0, upBytesPerSec: 0, rssi: -55, noise: -95, wifiConnected: true),
             temperatures: TemperatureReading(socC: 40))
}

/// Fait avancer le temps jusqu'à ce que l'hystérésis laisse passer le changement.
private func settle(_ e: inout HealthEngine, _ s: Snapshot, from t0: Date, seconds: Double = 40) -> HealthReport {
    var report = e.evaluate(s, now: t0)
    var t = t0
    while t.timeIntervalSince(t0) < seconds { t.addTimeInterval(1); var x = s; x.date = t; report = e.evaluate(x, now: t) }
    return report
}

@Suite("HealthEngine")
struct HealthEngineTests {
    @Test func healthyMacIsGreen() {
        var e = HealthEngine()
        let r = e.evaluate(baseSnapshot())
        #expect(r.globalScore >= 95)
        #expect(r.globalLevel == .ok)
        #expect(r.summary == "Ton Mac va bien")
    }

    @Test func fullDiskTurnsSSDRed() {
        var e = HealthEngine()
        var s = baseSnapshot(); s.disk = DiskReading(totalBytes: 500 << 30, freeBytes: 10 << 30, readBytesPerSec: 0, writeBytesPerSec: 0)
        let r = settle(&e, s, from: .now)
        let ssd = r.health(for: .ssd)!
        #expect(ssd.score == 30)   // -70 (< 5 % libre → 2 %)
        #expect(ssd.level == .critical)
    }

    @Test func diskTiers() {
        var e = HealthEngine()
        func score(free: Double) -> Double {
            var s = baseSnapshot(); s.disk = DiskReading(totalBytes: 1000, freeBytes: UInt64(free * 1000), readBytesPerSec: 0, writeBytesPerSec: 0)
            return e.evaluate(s).health(for: .ssd)!.score
        }
        #expect(score(free: 0.14) == 80)
        #expect(score(free: 0.09) == 60)
        #expect(score(free: 0.04) == 30)
    }

    @Test func memoryPressureAndSwap() {
        var e = HealthEngine()
        var s = baseSnapshot()
        s.memory?.pressure = .warning
        #expect(e.evaluate(s).health(for: .memory)!.score == 75)
        s.memory?.pressure = .critical; s.memory?.swapUsedBytes = 5 << 30
        #expect(e.evaluate(s).health(for: .memory)!.score == 25)
    }

    @Test func thermalPressurePenalties() {
        for (p, expected) in [(ThermalPressure.nominal, 100.0), (.moderate, 80), (.heavy, 50), (.critical, 20)] {
            var e = HealthEngine(); var s = baseSnapshot(); s.thermal = p
            #expect(e.evaluate(s).health(for: .chip)!.score == expected)
        }
    }

    @Test func worstComponentCapsGlobalScore() {
        var e = HealthEngine(); var s = baseSnapshot()
        s.thermal = .critical                   // chip = 20
        let r = e.evaluate(s)
        #expect(r.globalScore <= 45)            // min(avg, 20 + 25)
        #expect(r.globalLevel == .critical)
    }

    @Test func highLoadAloneIsNotAProblem() {
        var e = HealthEngine(); var s = baseSnapshot()
        s.cpu = CPUReading(perfLoad: [1, 1, 1, 1], effLoad: Array(repeating: 1, count: 6))
        s.foregroundApp = "Xcode"
        s.topProcesses = [ProcessUsage(pid: 1, name: "Xcode", cpuPercent: 380, memoryBytes: 0)]
        let r = settle(&e, s, from: .now, seconds: 400)
        #expect(r.health(for: .performanceCores)!.score == 100)
    }

    @Test func backgroundHogIsPenalisedAfterFiveMinutes() {
        var e = HealthEngine(); var s = baseSnapshot()
        s.foregroundApp = "Safari"
        s.topProcesses = [ProcessUsage(pid: 9, name: "mining", cpuPercent: 99, memoryBytes: 0)]
        let early = settle(&e, s, from: .now, seconds: 60)
        #expect(early.health(for: .performanceCores)!.score == 100)
        let late = settle(&e, s, from: .now.addingTimeInterval(1000), seconds: 400)
        #expect(late.health(for: .performanceCores)!.score == 85)
    }

    @Test func batteryWearAndHeat() {
        var e = HealthEngine(); var s = baseSnapshot()
        s.battery?.maxCapacityFraction = 0.78
        #expect(e.evaluate(s).health(for: .battery)!.score == 70)
        s.battery?.isCharging = true; s.battery?.temperatureC = 43
        #expect(e.evaluate(s).health(for: .battery)!.score == 50)
    }

    @Test func weakWiFi() {
        var e = HealthEngine(); var s = baseSnapshot(); s.network?.rssi = -80
        #expect(e.evaluate(s).health(for: .wireless)!.score == 80)
    }

    @Test func missingDataIsUnavailableNotCrash() {
        var e = HealthEngine()
        let r = e.evaluate(Snapshot())
        #expect(r.health(for: .battery)!.level == .unavailable)
        #expect(r.globalScore == 100)
    }

    @Test func hysteresisDelaysDegradationAndRecovery() {
        var e = HealthEngine(); let t0 = Date()
        var s = baseSnapshot(); s.thermal = .heavy
        _ = e.evaluate(baseSnapshot(at: t0), now: t0)                       // état initial : vert
        let a = e.evaluate(s, now: t0.addingTimeInterval(1))                 // chaud depuis 0 s
        #expect(a.health(for: .chip)!.level == .ok)
        let b = e.evaluate(s, now: t0.addingTimeInterval(12))                // > 10 s → ambre/rouge
        #expect(b.health(for: .chip)!.level == .warning)
        let c = e.evaluate(baseSnapshot(), now: t0.addingTimeInterval(15))   // refroidi depuis 0 s
        #expect(c.health(for: .chip)!.level == .warning)
        let d = e.evaluate(baseSnapshot(), now: t0.addingTimeInterval(50))   // > 30 s → vert
        #expect(d.health(for: .chip)!.level == .ok)
    }
}

@Suite("AlertEngine")
struct AlertEngineTests {
    @Test func diskAlertIsRateLimited() {
        var e = AlertEngine(); var s = baseSnapshot()
        s.disk = DiskReading(totalBytes: 1000, freeBytes: 50, readBytesPerSec: 0, writeBytesPerSec: 0)
        let t0 = Date()
        #expect(e.evaluate(s, now: t0).count == 1)
        #expect(e.evaluate(s, now: t0.addingTimeInterval(600)).isEmpty)           // anti-spam 30 min
        #expect(e.evaluate(s, now: t0.addingTimeInterval(31 * 60)).count == 1)
    }

    @Test func throttlingNeedsTwoMinutes() {
        var e = AlertEngine(); var s = baseSnapshot(); s.thermal = .heavy
        let t0 = Date()
        #expect(e.evaluate(s, now: t0).isEmpty)
        #expect(e.evaluate(s, now: t0.addingTimeInterval(60)).isEmpty)
        let fired = e.evaluate(s, now: t0.addingTimeInterval(121))
        #expect(fired.first?.kind == .throttling)
    }

    @Test func disabledKindsStaySilent() {
        var e = AlertEngine(); e.enabled = []
        var s = baseSnapshot(); s.disk = DiskReading(totalBytes: 1000, freeBytes: 10, readBytesPerSec: 0, writeBytesPerSec: 0)
        #expect(e.evaluate(s).isEmpty)
    }

    @Test func healthyMacRaisesNothing() {
        var e = AlertEngine()
        #expect(e.evaluate(baseSnapshot()).isEmpty)
    }
}

@Suite("MetricStore")
struct MetricStoreTests {
    @Test func ringBufferKeepsCapacity() {
        var store = MetricStore(capacity: 5)
        for i in 0..<20 { var s = baseSnapshot(at: Date(timeIntervalSince1970: Double(i))); s.cpu = CPUReading(perfLoad: [Double(i) / 20], effLoad: [0]); store.append(s) }
        let series = store.series(.cpuPerf)
        #expect(series.count == 5)
        #expect(series.last?.value == 19.0 / 20)
        #expect(store.series(.cpuPerf, last: 2).count == 3)
    }
}
