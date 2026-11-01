import Foundation
import GRDB

public enum HistoryRange: String, CaseIterable, Sendable, Identifiable {
    case hour = "1 h", day = "24 h", week = "7 j"
    public var id: String { rawValue }
    public var seconds: TimeInterval {
        switch self { case .hour: 3600; case .day: 86400; case .week: 7 * 86400 }
    }
    /// Résolution de la table utilisée.
    var bucket: Int { self == .week ? 900 : 60 }
}

public struct HistoryPoint: Sendable, Equatable, Identifiable {
    public var date: Date
    public var average: Double
    public var maximum: Double
    public var id: Date { date }
}

public struct AlertRecord: Sendable, Equatable, Identifiable, Codable {
    public var id: Int64?
    public var date: Date
    public var kind: String
    public var component: String
    public var title: String
    public var body: String
    public var severity: String
    public init(id: Int64? = nil, date: Date, kind: String, component: String, title: String, body: String, severity: String) {
        self.id = id; self.date = date; self.kind = kind; self.component = component
        self.title = title; self.body = body; self.severity = severity
    }
}

/// Historique SQLite : agrégation à 1 min et 15 min, rétention 30 jours.
/// Les échantillons sont regroupés en mémoire puis écrits par lots (une écriture par minute).
public actor HistoryRepository {
    public static let retention1m: TimeInterval = 7 * 86400
    public static let retention15m: TimeInterval = 30 * 86400

    private let db: DatabaseQueue
    public let path: String?

    private struct Acc { var sum = 0.0; var max = -Double.infinity; var n = 0 }
    private var bucketStart: Int = 0
    private var acc: [String: Acc] = [:]

    public init(path: String?) throws {
        self.path = path
        if let path {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            var config = Configuration()
            config.prepareDatabase { try $0.execute(sql: "PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;") }
            db = try DatabaseQueue(path: path, configuration: config)
        } else {
            db = try DatabaseQueue()
        }
        try Self.migrate(db)
    }

    private static func migrate(_ db: DatabaseQueue) throws {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            for table in ["metric_1m", "metric_15m"] {
                try db.create(table: table, options: [.withoutRowID]) { t in
                    t.column("ts", .integer).notNull()
                    t.column("metric", .text).notNull()
                    t.column("sum", .double).notNull()
                    t.column("max", .double).notNull()
                    t.column("n", .integer).notNull()
                    t.primaryKey(["ts", "metric"])
                }
            }
            try db.create(table: "alert") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("ts", .integer).notNull().indexed()
                t.column("kind", .text).notNull()
                t.column("component", .text).notNull()
                t.column("title", .text).notNull()
                t.column("body", .text).notNull()
                t.column("severity", .text).notNull()
            }
        }
        try m.migrate(db)
    }

    // MARK: Écriture

    /// Ajoute un échantillon ; écrit un lot quand la minute change.
    public func record(date: Date, values: [String: Double]) {
        let minute = Int(date.timeIntervalSince1970) / 60 * 60
        if bucketStart == 0 { bucketStart = minute }
        if minute != bucketStart { try? flush(); bucketStart = minute }
        for (k, v) in values where v.isFinite {
            var a = acc[k, default: Acc()]
            a.sum += v; a.max = Swift.max(a.max, v); a.n += 1
            acc[k] = a
        }
    }

    /// Écrit le seau courant dans les tables 1 min et 15 min (fusion pondérée).
    public func flush() throws {
        guard !acc.isEmpty else { return }
        let snapshot = acc; let ts1 = bucketStart; let ts15 = ts1 / 900 * 900
        acc = [:]
        try db.write { db in
            for (metric, a) in snapshot {
                for (table, ts) in [("metric_1m", ts1), ("metric_15m", ts15)] {
                    try db.execute(sql: """
                        INSERT INTO \(table)(ts, metric, sum, max, n) VALUES (?, ?, ?, ?, ?)
                        ON CONFLICT(ts, metric) DO UPDATE SET
                          sum = sum + excluded.sum, n = n + excluded.n, max = MAX(max, excluded.max)
                        """, arguments: [ts, metric, a.sum, a.max, a.n])
                }
            }
        }
    }

    public func prune(now: Date = .now) throws {
        let t = now.timeIntervalSince1970
        try db.write { db in
            try db.execute(sql: "DELETE FROM metric_1m WHERE ts < ?", arguments: [Int(t - Self.retention1m)])
            try db.execute(sql: "DELETE FROM metric_15m WHERE ts < ?", arguments: [Int(t - Self.retention15m)])
            try db.execute(sql: "DELETE FROM alert WHERE ts < ?", arguments: [Int(t - Self.retention15m)])
        }
        try db.writeWithoutTransaction { try $0.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)") }
    }

    public func record(alert: AlertRecord) throws {
        try db.write { db in
            try db.execute(sql: "INSERT INTO alert(ts, kind, component, title, body, severity) VALUES (?,?,?,?,?,?)",
                           arguments: [Int(alert.date.timeIntervalSince1970), alert.kind, alert.component, alert.title, alert.body, alert.severity])
        }
    }

    // MARK: Lecture

    public func series(metric: String, range: HistoryRange, now: Date = .now) throws -> [HistoryPoint] {
        try? flush()
        let table = range.bucket == 900 ? "metric_15m" : "metric_1m"
        let from = Int(now.timeIntervalSince1970 - range.seconds)
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT ts, sum, max, n FROM \(table) WHERE metric = ? AND ts >= ? ORDER BY ts",
                             arguments: [metric, from])
        }
        let points = rows.map { r -> HistoryPoint in
            let n = Swift.max(1, r["n"] as Int)
            return HistoryPoint(date: Date(timeIntervalSince1970: TimeInterval(r["ts"] as Int)),
                                average: (r["sum"] as Double) / Double(n), maximum: r["max"] as Double)
        }
        // Le 24 h agrège les minutes par tranches de 5 min pour limiter le nombre de points.
        guard range == .day else { return points }
        var grouped: [Int: (sum: Double, max: Double, c: Int)] = [:]
        for p in points {
            let k = Int(p.date.timeIntervalSince1970) / 300 * 300
            var g = grouped[k, default: (0, -.infinity, 0)]
            g.sum += p.average; g.max = Swift.max(g.max, p.maximum); g.c += 1
            grouped[k] = g
        }
        return grouped.keys.sorted().map { k in
            let g = grouped[k]!
            return HistoryPoint(date: Date(timeIntervalSince1970: TimeInterval(k)), average: g.sum / Double(g.c), maximum: g.max)
        }
    }

    public func recentAlerts(limit: Int = 20) throws -> [AlertRecord] {
        try db.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM alert ORDER BY ts DESC LIMIT ?", arguments: [limit]).map {
                AlertRecord(id: $0["id"], date: Date(timeIntervalSince1970: TimeInterval($0["ts"] as Int)),
                            kind: $0["kind"], component: $0["component"], title: $0["title"], body: $0["body"], severity: $0["severity"])
            }
        }
    }

    /// Taille du fichier de base sur disque (octets).
    public func fileSize() -> Int64 {
        guard let path else { return 0 }
        let fm = FileManager.default
        return ["", "-wal", "-shm"].reduce(0) { $0 + ((try? fm.attributesOfItem(atPath: path + $1)[.size] as? Int64) ?? 0) }
    }
}
