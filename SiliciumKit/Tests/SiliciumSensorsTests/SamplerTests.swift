import Testing
import Foundation
import SiliciumShared
@testable import SiliciumSensors

@Suite("Samplers (machine réelle)")
struct SamplerTests {
    @Test func cpuLoadsAreFractions() throws {
        let s = CPUSampler()
        _ = try s.sample()
        Thread.sleep(forTimeInterval: 0.3)
        let r = try s.sample()
        #expect(r.perfLoad.count + r.effLoad.count == ProcessInfo.processInfo.processorCount)
        #expect((r.perfLoad + r.effLoad).allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    @Test func memoryIsCoherent() throws {
        let m = try MemorySampler().sample()
        #expect(m.totalBytes == ProcessInfo.processInfo.physicalMemory)
        #expect(m.usedBytes > 0 && m.usedBytes <= m.totalBytes)
    }

    @Test func diskHasCapacity() throws {
        let d = try DiskSampler().sample()
        #expect(d.totalBytes > 0 && d.freeBytes <= d.totalBytes)
    }

    @Test func thermalDoesNotCrash() throws { _ = try ThermalSampler().sample() }

    @Test func processesSeeCurrentProcess() throws {
        let p = ProcessSampler()
        _ = try p.sample()
        Thread.sleep(forTimeInterval: 0.3)
        #expect(try !p.sample().isEmpty)
    }
}
