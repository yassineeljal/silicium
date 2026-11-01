import Foundation
import CoreFoundation

/// Liaison dynamique à `libIOReport.dylib` (API privée, aucun stub dans le SDK).
/// Si la bibliothèque ou un symbole manque, `IOReportBridge.shared` vaut `nil` et la
/// composante passe en « donnée indisponible » au lieu de faire planter l'app.
final class IOReportBridge: @unchecked Sendable {
    typealias CopyChannelsInGroup = @convention(c) (CFString, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    typealias MergeChannels = @convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void
    typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> UnsafeRawPointer?
    typealias CreateSamples = @convention(c) (UnsafeRawPointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias Iterate = @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void
    typealias GetString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    typealias SimpleValue = @convention(c) (CFDictionary, Int32) -> Int64
    typealias StateCount = @convention(c) (CFDictionary) -> Int32
    typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    typealias StateResidency = @convention(c) (CFDictionary, Int32) -> Int64

    let copyChannelsInGroup: CopyChannelsInGroup
    let mergeChannels: MergeChannels
    let createSubscription: CreateSubscription
    let createSamples: CreateSamples
    let createSamplesDelta: CreateSamplesDelta
    let iterate: Iterate
    let groupName: GetString
    let subGroupName: GetString
    let channelName: GetString
    let unitLabel: GetString
    let simpleValue: SimpleValue
    let stateCount: StateCount
    let stateName: StateName
    let stateResidency: StateResidency

    static let shared: IOReportBridge? = IOReportBridge()

    private init?() {
        guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func sym<T>(_ n: String, _ t: T.Type) -> T? {
            guard let p = dlsym(h, n) else { return nil }
            return unsafeBitCast(p, to: t)
        }
        guard let a = sym("IOReportCopyChannelsInGroup", CopyChannelsInGroup.self),
              let b = sym("IOReportMergeChannels", MergeChannels.self),
              let c = sym("IOReportCreateSubscription", CreateSubscription.self),
              let d = sym("IOReportCreateSamples", CreateSamples.self),
              let e = sym("IOReportCreateSamplesDelta", CreateSamplesDelta.self),
              let f = sym("IOReportIterate", Iterate.self),
              let g = sym("IOReportChannelGetGroup", GetString.self),
              let g2 = sym("IOReportChannelGetSubGroup", GetString.self),
              let g3 = sym("IOReportChannelGetChannelName", GetString.self),
              let g4 = sym("IOReportChannelGetUnitLabel", GetString.self),
              let h1 = sym("IOReportSimpleGetIntegerValue", SimpleValue.self),
              let h2 = sym("IOReportStateGetCount", StateCount.self),
              let h3 = sym("IOReportStateGetNameForIndex", StateName.self),
              let h4 = sym("IOReportStateGetResidency", StateResidency.self)
        else { return nil }
        copyChannelsInGroup = a; mergeChannels = b; createSubscription = c; createSamples = d
        createSamplesDelta = e; iterate = f; groupName = g; subGroupName = g2; channelName = g3
        unitLabel = g4; simpleValue = h1; stateCount = h2; stateName = h3; stateResidency = h4
    }
}

/// Un abonnement IOReport sur un ensemble de groupes, avec échantillonnage différentiel.
final class IOReportSubscription {
    struct Channel {
        let group: String
        let subGroup: String
        let name: String
        let unit: String
        let value: Int64
        let states: [(name: String, residency: Int64)]
    }

    private let bridge: IOReportBridge
    private let sub: UnsafeRawPointer
    private let channels: CFMutableDictionary
    private var previous: CFDictionary?
    private var previousTime: Double = 0

    init?(groups: [(String, String?)]) {
        guard let bridge = IOReportBridge.shared else { return nil }
        self.bridge = bridge
        var merged: CFMutableDictionary?
        for (g, sg) in groups {
            guard let ch = bridge.copyChannelsInGroup(g as CFString, sg as CFString?, 0, 0, 0)?.takeRetainedValue() else { continue }
            if let m = merged { bridge.mergeChannels(m, ch, nil) } else { merged = ch }
        }
        guard let merged else { return nil }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let s = bridge.createSubscription(nil, merged, &subbed, 0, nil) else { return nil }
        self.sub = s
        self.channels = merged
    }

    /// Retourne les canaux différentiels depuis le dernier appel, et la durée écoulée (s).
    func sampleDelta() -> (channels: [Channel], seconds: Double)? {
        guard let cur = bridge.createSamples(sub, channels, nil)?.takeRetainedValue() else { return nil }
        let now = monotonicSeconds()
        defer { previous = cur; previousTime = now }
        guard let prev = previous, let delta = bridge.createSamplesDelta(prev, cur, nil)?.takeRetainedValue() else { return nil }
        var out: [Channel] = []
        let b = bridge
        bridge.iterate(delta) { item in
            let group = b.groupName(item)?.takeUnretainedValue() as String? ?? ""
            let sub = b.subGroupName(item)?.takeUnretainedValue() as String? ?? ""
            let name = b.channelName(item)?.takeUnretainedValue() as String? ?? ""
            let unit = (b.unitLabel(item)?.takeUnretainedValue() as String? ?? "").trimmingCharacters(in: .whitespaces)
            var states: [(String, Int64)] = []
            let n = b.stateCount(item)
            if n > 0 && n < 256 {
                for i in 0..<n {
                    states.append((b.stateName(item, i)?.takeUnretainedValue() as String? ?? "", b.stateResidency(item, i)))
                }
            }
            out.append(Channel(group: group, subGroup: sub, name: name, unit: unit,
                               value: n > 0 ? 0 : b.simpleValue(item, 0), states: states))
            return 0
        }
        return (out, max(0.001, now - previousTime))
    }
}
