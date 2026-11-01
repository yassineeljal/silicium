import Testing
import Foundation
@testable import SiliciumStorage

@Suite("HistoryRepository")
struct HistoryRepositoryTests {
    @Test func aggregatesPerMinute() async throws {
        let repo = try HistoryRepository(path: nil)
        let base = Date(timeIntervalSince1970: TimeInterval(1_800_000_000 - 1_800_000_000 % 60))
        for i in 0..<60 { await repo.record(date: base.addingTimeInterval(Double(i)), values: ["cpu": Double(i)]) }
        await repo.record(date: base.addingTimeInterval(61), values: ["cpu": 100])   // change de minute → flush
        let pts = try await repo.series(metric: "cpu", range: .hour, now: base.addingTimeInterval(120))
        #expect(pts.count == 2)
        #expect(abs(pts[0].average - 29.5) < 0.001)
        #expect(pts[0].maximum == 59)
    }

    @Test func weekUses15MinuteBuckets() async throws {
        let repo = try HistoryRepository(path: nil)
        let base = Date(timeIntervalSince1970: TimeInterval(1_800_000_000 - 1_800_000_000 % 900))
        for m in 0..<45 { await repo.record(date: base.addingTimeInterval(Double(m) * 60), values: ["x": 1]) }
        let pts = try await repo.series(metric: "x", range: .week, now: base.addingTimeInterval(3000))
        #expect(pts.count == 3)
    }

    @Test func pruneRemovesOldRows() async throws {
        let repo = try HistoryRepository(path: nil)
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        await repo.record(date: old, values: ["x": 1])
        try await repo.flush()
        try await repo.prune(now: old.addingTimeInterval(40 * 86400))
        let pts = try await repo.series(metric: "x", range: .week, now: old)
        #expect(pts.isEmpty)
    }

    @Test func storesAlerts() async throws {
        let repo = try HistoryRepository(path: nil)
        try await repo.record(alert: AlertRecord(date: .now, kind: "diskFull", component: "ssd", title: "t", body: "b", severity: "warning"))
        let a = try await repo.recentAlerts()
        #expect(a.count == 1)
        #expect(a[0].kind == "diskFull")
    }

    @Test func eightDaysOfMinuteDataStaysUnder50MB() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("silicium-test-\(UUID().uuidString)")
        let repo = try HistoryRepository(path: dir.appendingPathComponent("h.sqlite").path)
        let base = Date(timeIntervalSince1970: TimeInterval(1_800_000_000 - 1_800_000_000 % 60))
        let names = (0..<21).map { "metric\($0)" }
        // 8 jours à 1 échantillon/min (pire cas de la table 1 min, rétention 7 j) suffisent pour mesurer la taille (agrégation par minute).
        for m in 0..<(8 * 24 * 60) {
            await repo.record(date: base.addingTimeInterval(Double(m) * 60), values: Dictionary(uniqueKeysWithValues: names.map { ($0, Double(m % 100)) }))
        }
        try await repo.flush(); try await repo.prune(now: base.addingTimeInterval(8 * 86400))
        let size = await repo.fileSize()
        #expect(size < 50 * 1_048_576, "taille: \(size)")
        try? FileManager.default.removeItem(at: dir)
    }
}
