import AppKit
import SwiftUI
import SiliciumUI
import SiliciumShared

/// Mode de capture pour vérifier le rendu sans interaction : `Silicium --snapshot out.png [--select chip] [--exploded]`.
@MainActor
enum Debug {
    /// Rendu hors-écran : `Silicium --render out.png [--yaw y --pitch p --dist d] [--select id] [--exploded]`
    static func renderOffline(path: String, args: [String]) {
        func arg(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        Task { @MainActor in
            await DebugHooks.renderOffline(to: path, yaw: arg("--yaw").flatMap(Float.init), pitch: arg("--pitch").flatMap(Float.init),
                                           distance: arg("--dist").flatMap(Float.init), exploded: args.contains("--exploded"),
                                           selection: arg("--select").flatMap(ComponentID.init(rawValue:)), hovered: arg("--hover").flatMap(ComponentID.init(rawValue:)))
            exit(0)
        }
    }

    static func scheduleSnapshot(path: String, args: [String]) {
        Task { @MainActor in
            for _ in 0..<40 {
                AppDelegate.openMain()
                try? await Task.sleep(for: .milliseconds(250))
                if NSApp.windows.contains(where: { $0.title == "Silicium" && $0.isVisible }) { break }
            }
            if let i = args.firstIndex(of: "--select"), i + 1 < args.count, let id = ComponentID(rawValue: args[i + 1]) { Shared.model.select(id) }
            if args.contains("--exploded") { Shared.model.exploded = true }
            NSLog("SNAP windows visible")
            try? await Task.sleep(for: .seconds(5))
            NSLog("SNAP capturing")
            if args.contains("--verify-interactions") {
                do { print(try DebugHooks.verifyPicking()) }
                catch { print("PICKING_INVALID: \(error)"); exit(1) }
            }
            func arg(_ k: String) -> Float? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? Float(args[$0 + 1]) : nil } }
            if let y = arg("--yaw"), let p = arg("--pitch"), let d = arg("--dist") { DebugHooks.setCamera(yaw: y, pitch: p, distance: d); try? await Task.sleep(for: .seconds(2)) }
            if args.contains("--snapshot-ui") {
                DebugHooks.saveWindowSnapshot(to: path, model: Shared.model) { NSLog("SNAP UI done"); exit(0) }
            } else {
                DebugHooks.saveSceneSnapshot(to: path) { NSLog("SNAP done"); exit(0) }
            }
        }
    }
}
