import Foundation

public struct ComponentHealth: Sendable, Codable, Equatable, Identifiable {
    public var component: ComponentID
    public var score: Double
    public var level: HealthLevel
    /// Raison du score en une phrase.
    public var reason: String
    /// Intensité de charge 0…1 qui pilote la lumière dans la scène 3D.
    public var load: Double
    /// Valeur clé affichée (« 42 % », « 8,3 W »…).
    public var headline: String
    public var id: ComponentID { component }
    public init(component: ComponentID, score: Double, level: HealthLevel, reason: String, load: Double, headline: String) {
        self.component = component; self.score = score; self.level = level
        self.reason = reason; self.load = load; self.headline = headline
    }
}

public struct HealthReport: Sendable, Codable, Equatable {
    public var date: Date
    public var globalScore: Double
    public var globalLevel: HealthLevel
    public var summary: String
    public var components: [ComponentHealth]
    public init(date: Date = .now, globalScore: Double, globalLevel: HealthLevel, summary: String, components: [ComponentHealth]) {
        self.date = date; self.globalScore = globalScore; self.globalLevel = globalLevel
        self.summary = summary; self.components = components
    }

    public func health(for id: ComponentID) -> ComponentHealth? { components.first { $0.component == id } }

    /// Composantes à surveiller, du pire au moins grave (max `limit`).
    public func watchlist(limit: Int = 3) -> [ComponentHealth] {
        components.filter { $0.level == .warning || $0.level == .critical }
            .sorted { $0.score < $1.score }
            .prefix(limit).map { $0 }
    }

    public static let initial = HealthReport(globalScore: 100, globalLevel: .ok, summary: "Analyse en cours…", components: [])
}
