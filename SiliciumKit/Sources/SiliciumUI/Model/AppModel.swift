import Foundation
import AppKit
import Observation
import UserNotifications
import SiliciumShared
import SiliciumSensors
import SiliciumCore
import SiliciumStorage

/// Chef d'orchestre : branche le `SensorHub` sur le moteur de santé, l'historique, les alertes et l'interface.
@MainActor @Observable
public final class AppModel {
    // État observable par les vues
    public private(set) var snapshot = Snapshot.empty
    public private(set) var report = HealthReport.initial
    public private(set) var store = MetricStore()
    public private(set) var recentAlerts: [AlertRecord] = []
    public private(set) var hasData = false
    public private(set) var gpuCoreCount = 8

    public var selection: ComponentID?
    var selectionRevision = 0
    public var hovered: ComponentID?
    public var hoverLocation: CGPoint = .zero
    public var showDiagnosis = false
    public var showBatteryReport = false
    public var resetCameraToken = 0
    public var exploded = false
    public var inspectChip = false
    public var showLabels = true
    public var cameraPreset: SceneCameraPreset = .perspective
    public var zoomStep = 0
    let annotations = SceneAnnotations()
    var reviewSceneImage: NSImage?

    public var windowOpen = false { didSet { Task { await updateMode() } } }
    public var panelOpen = false { didSet { Task { await updateMode() } } }

    public let settings: AppSettings
    public let hub: SensorHub
    public let history: HistoryRepository?

    private var engine = HealthEngine()
    private var alertEngine = AlertEngine()
    private var started = false
    private var lastPersist = Date.distantPast
    private var lastPrune = Date.distantPast
    private var lastKnownMode: SamplingMode?

    public init(settings: AppSettings = AppSettings(), hub: SensorHub = SensorHub(), historyPath: String? = AppModel.defaultHistoryPath) {
        self.settings = settings
        self.hub = hub
        self.history = try? HistoryRepository(path: historyPath)
    }

    public static var defaultHistoryPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Silicium/history.sqlite").path
    }

    public var isInteractive: Bool { windowOpen || panelOpen }

    // MARK: Démarrage

    public func start() {
        guard !started else { return }
        started = true
        settings.applied(to: &alertEngine)
        settings.applied(to: &engine.thresholds)
        Task { await self.configureNotifications() }
        observeForegroundApp()
        Task {
            await hub.start()
            await updateMode()
            for await s in await hub.updates() { ingest(s) }
        }
        Task { await refreshAlerts() }
    }

    public func applySettings() {
        settings.applied(to: &alertEngine)
        settings.applied(to: &engine.thresholds)
    }

    private func observeForegroundApp() {
        let ws = NSWorkspace.shared
        Task { await hub.setForegroundApp(ws.frontmostApplication?.localizedName) }
        NotificationCenter.default.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: ws, queue: .main) { [hub] note in
            let name = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName
            Task { await hub.setForegroundApp(name) }
        }
    }

    // MARK: Pipeline

    private func ingest(_ s: Snapshot) {
        snapshot = s
        store.append(s)
        let r = engine.evaluate(s, now: s.date)
        report = r
        hasData = true
        if let n = s.gpu { _ = n }

        for alert in alertEngine.evaluate(s, now: s.date) where settings.alertsEnabled {
            deliver(alert)
        }
        persist(s)
        Task { await updateMode() }
    }

    private func persist(_ s: Snapshot) {
        guard let history else { return }
        var values: [String: Double] = [:]
        for m in Metric.allCases { if let v = Metric.value(m, in: s) { values[m.rawValue] = v } }
        for c in report.components where c.level != .unavailable { values["score." + c.component.rawValue] = c.score }
        values["score.global"] = report.globalScore
        let date = s.date
        Task {
            await history.record(date: date, values: values)
            if date.timeIntervalSince(lastPrune) > 6 * 3600 { lastPrune = date; try? await history.prune(now: date) }
        }
    }

    private func updateMode() async {
        let mode: SamplingMode
        if isInteractive { mode = .interactive }
        else if snapshot.lowPowerMode { mode = .lowPower }
        else if snapshot.battery?.onACPower == false { mode = .backgroundBattery }
        else { mode = .backgroundAC }
        guard mode != lastKnownMode else { return }
        lastKnownMode = mode
        await hub.setMode(mode)
    }

    // MARK: Alertes

    private func configureNotifications() async {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "SILICIUM_ALERT",
                                   actions: [UNNotificationAction(identifier: "VIEW", title: "Voir", options: [.foreground])],
                                   intentIdentifiers: [])
        ])
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func deliver(_ alert: HealthAlert) {
        if let history {
            let rec = AlertRecord(date: alert.date, kind: alert.kind.rawValue, component: alert.component.rawValue,
                                  title: alert.title, body: alert.body, severity: alert.severity.rawValue)
            Task { try? await history.record(alert: rec); await refreshAlerts() }
        }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.categoryIdentifier = "SILICIUM_ALERT"
        content.userInfo = ["component": alert.component.rawValue]
        content.sound = alert.severity == .critical ? .default : nil
        let req = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    public func refreshAlerts() async {
        if let history, let a = try? await history.recentAlerts(limit: 12) { recentAlerts = a }
    }

    // MARK: Aide pour les vues

    public func health(_ id: ComponentID) -> ComponentHealth? { report.health(for: id) }

    public func select(_ id: ComponentID?) {
        selection = id
        selectionRevision += 1
        hovered = nil
        if let id, ComponentInfo.isInsideChip(id) { inspectChip = true }
        else if id != .chip { inspectChip = false }
    }

    public func showOverview() {
        select(nil)
        exploded = false
        inspectChip = false
        cameraPreset = .perspective
        resetCameraToken += 1
    }

    public func setView(_ preset: SceneCameraPreset) {
        cameraPreset = preset
        resetCameraToken += 1
    }

    public var diagnosis: Diagnosis { DiagnosisEngine.diagnose(snapshot, report: report) }

    /// Titre d'accessibilité / tooltip de la barre des menus.
    public var menuBarTooltip: String { "Silicium — \(Int(report.globalScore.rounded())) % · \(report.summary)" }
}
