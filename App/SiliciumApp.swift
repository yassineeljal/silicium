import SwiftUI
import AppKit
import UserNotifications
import SiliciumUI
import SiliciumShared

@MainActor
enum Shared {
    static let model = AppModel()
    /// Renseigné au lancement par la scène (seule `openWindow` sait ouvrir une fenêtre SwiftUI).
    static var openMainWindow: (() -> Void)?
}

/// Agent sans Dock (`LSUIElement`) : le Dock apparaît seulement pendant que la fenêtre 3D est ouverte.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ProcessInfo.processInfo.arguments.contains("--render") && !ProcessInfo.processInfo.arguments.contains("--verify-model") { Shared.model.start() }
        if Bundle.main.bundleURL.pathExtension == "app" { UNUserNotificationCenter.current().delegate = self }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--verify-model") {
            do { print(try DebugHooks.validateModel()); exit(0) }
            catch { print("MODEL_INVALID: \(error)"); exit(1) }
        }
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            Debug.renderOffline(path: args[i + 1], args: args); return
        }
        if args.contains("--open-main") {
            Task { @MainActor in try? await Task.sleep(for: .milliseconds(300)); Self.openMain() }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Debug.scheduleSnapshot(path: args[i + 1], args: args)
        }
        if let i = args.firstIndex(of: "--snapshot-ui"), i + 1 < args.count {
            Debug.scheduleSnapshot(path: args[i + 1], args: args)
        }
    }

    @MainActor static func openMain() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.title == "Silicium" && !($0 is NSPanel) }) { w.makeKeyAndOrderFront(nil) }
        else { Shared.openMainWindow?() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let comp = response.notification.request.content.userInfo["component"] as? String
        await MainActor.run {
            if let comp, let id = ComponentID(rawValue: comp) { Shared.model.select(id) }
            Self.openMain()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct SiliciumApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    private let model = Shared.model

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: model, openMain: showMain, openSettings: { NSApp.activate(ignoringOtherApps: true); openSettings() })
        } label: {
            MenuBarLabel(model: model)
                .onAppear { Shared.openMainWindow = { openWindow(id: "main") } }
        }
        .menuBarExtraStyle(.window)

        Window("Silicium", id: "main") {
            MainWindow(model: model)
                .onAppear { NSApp.setActivationPolicy(.regular) }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultSize(width: 1360, height: 860)
        .defaultLaunchBehavior(.suppressed)

        Settings { SettingsView(model: model) }
    }

    private func showMain() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
