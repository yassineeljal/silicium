import Foundation
import Observation
import ServiceManagement
import SiliciumCore
import SiliciumShared

public enum MenuBarStyle: String, CaseIterable, Identifiable, Sendable {
    case chip = "Puce colorée"
    case score = "Score en chiffres"
    public var id: String { rawValue }
}

/// Réglages persistés dans UserDefaults.
@MainActor @Observable
public final class AppSettings {
    private let defaults: UserDefaults

    public var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    public var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: "alertsEnabled") } }
    public var disabledAlertKinds: Set<String> { didSet { defaults.set(Array(disabledAlertKinds), forKey: "disabledAlertKinds") } }
    public var diskAlertThreshold: Double { didSet { defaults.set(diskAlertThreshold, forKey: "diskAlertThreshold") } }
    public var batteryHotThreshold: Double { didSet { defaults.set(batteryHotThreshold, forKey: "batteryHotThreshold") } }
    public var backgroundIntervalOverride: Double { didSet { defaults.set(backgroundIntervalOverride, forKey: "bgInterval") } }
    public var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }
    public var particlesEnabled: Bool { didSet { defaults.set(particlesEnabled, forKey: "particles") } }
    public var bloomEnabled: Bool { didSet { defaults.set(bloomEnabled, forKey: "bloom") } }

    public private(set) var launchAtLogin: Bool

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .chip
        alertsEnabled = defaults.object(forKey: "alertsEnabled") as? Bool ?? true
        disabledAlertKinds = Set(defaults.stringArray(forKey: "disabledAlertKinds") ?? [])
        diskAlertThreshold = defaults.object(forKey: "diskAlertThreshold") as? Double ?? 0.90
        batteryHotThreshold = defaults.object(forKey: "batteryHotThreshold") as? Double ?? 40
        backgroundIntervalOverride = defaults.object(forKey: "bgInterval") as? Double ?? 0
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        particlesEnabled = defaults.object(forKey: "particles") as? Bool ?? true
        bloomEnabled = defaults.object(forKey: "bloom") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    public func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Silicium: SMAppService a échoué: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func applied(to engine: inout AlertEngine) {
        engine.enabled = Set(HealthAlert.Kind.allCases.filter { !disabledAlertKinds.contains($0.rawValue) })
        engine.diskFullThreshold = diskAlertThreshold
    }

    func applied(to thresholds: inout HealthThresholds) {
        thresholds.batteryChargeHotC = batteryHotThreshold
        thresholds.diskFreeWarn = max(0.05, 1 - diskAlertThreshold + 0.05)
    }
}
