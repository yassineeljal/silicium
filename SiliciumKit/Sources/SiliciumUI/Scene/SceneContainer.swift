import SwiftUI
import RealityKit
import SiliciumShared
import SiliciumCore

/// Pont SwiftUI ↔ RealityKit. Le contrôleur vit dans le coordinateur ; chaque instantané pousse un `SceneInput`.
struct SceneContainer: NSViewRepresentable {
    let model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @MainActor
    final class Coordinator {
        let controller: SceneController
        var resetToken = 0
        var zoomStep = 0
        init(gpu: Int) { controller = SceneController(gpuCoreCount: gpu) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(gpu: model.gpuCoreCount) }

    func makeNSView(context: Context) -> SiliciumARView {
        let c = context.coordinator.controller
        c.onHover = { [weak model] id, point in
            guard let model else { return }
            model.hovered = id
            model.hoverLocation = point
        }
        c.onSelect = { [weak model] id in
            if let id { model?.select(id) } else { model?.showOverview() }
        }
        c.onToggleExplode = { [weak model] in model?.exploded.toggle() }
        c.onMarkers = { [weak model] markers in
            guard let model else { return }
            let previous = model.annotations.markers
            if previous.count != markers.count || zip(previous, markers).contains(where: {
                $0.id != $1.id || abs($0.point.x - $1.point.x) > 0.5 || abs($0.point.y - $1.point.y) > 0.5
            }) { model.annotations.markers = markers }
        }
        return c.view
    }

    func updateNSView(_ view: SiliciumARView, context: Context) {
        let c = context.coordinator.controller
        c.setBloom(model.settings.bloomEnabled && model.inspectChip)
        c.apply(SceneInput(model: model, reduceMotion: reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion))
        if context.coordinator.resetToken != model.resetCameraToken {
            context.coordinator.resetToken = model.resetCameraToken
            if model.selection == nil { c.resetCamera() }
            c.setView(model.cameraPreset)
        }
        if context.coordinator.zoomStep != model.zoomStep {
            let delta = model.zoomStep - context.coordinator.zoomStep
            context.coordinator.zoomStep = model.zoomStep
            c.zoom(by: delta > 0 ? -0.18 : 0.22)
        }
    }
}

extension SceneInput {
    @MainActor
    init(model: AppModel, reduceMotion: Bool) {
        self.init()
        let s = model.snapshot
        for c in model.report.components { level[c.component] = c.level; load[c.component] = Float(c.load) }
        perfLoads = (s.cpu?.perfLoad ?? []).map(Float.init)
        effLoads = (s.cpu?.effLoad ?? []).map(Float.init)
        gpuUtilization = Float(s.gpu?.utilization ?? 0)
        aneLoad = Float(min(1, (s.power?.aneWatts ?? 0) / 3))
        memoryUsed = Float(s.memory?.usedFraction ?? 0)
        memoryActivity = Float(min(1, (s.power?.dramWatts ?? 0) / 1.8 + (s.cpu?.overall ?? 0) * 0.4))
        diskUsed = Float(s.disk?.usedFraction ?? 0)
        diskActivity = Float(min(1, ((s.disk?.readBytesPerSec ?? 0) + (s.disk?.writeBytesPerSec ?? 0)) / 400_000_000))
        hasBattery = s.battery != nil
        batteryCharge = Float(s.battery?.chargeFraction ?? 0)
        batteryCharging = s.battery?.isCharging ?? false
        batteryDraw = Float(min(1, abs(s.battery?.watts ?? 0) / 30))
        onAC = s.battery?.onACPower ?? false
        netActivity = Float(min(1, ((s.network?.downBytesPerSec ?? 0) + (s.network?.upBytesPerSec ?? 0)) / 8_000_000))
        if let r = s.network?.rssi, s.network?.wifiConnected == true { signalBars = r > -60 ? 3 : (r > -72 ? 2 : 1) }
        chipTempC = Float(s.temperatures?.chipC ?? 38)
        thermalPressure = s.thermal.rawValue
        selection = model.selection
        selectionRevision = model.selectionRevision
        hovered = model.hovered
        exploded = model.exploded
        inspectChip = model.inspectChip
        particles = model.settings.particlesEnabled
        self.reduceMotion = reduceMotion
    }
}
