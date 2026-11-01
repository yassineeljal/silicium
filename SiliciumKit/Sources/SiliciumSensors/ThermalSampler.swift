import Foundation
import SiliciumShared

/// Pression thermique via `ProcessInfo.thermalState` (indicateur principal : le M5 Air n'a pas de ventilateur).
public final class ThermalSampler: Sampler {
    public typealias Reading = ThermalPressure
    public init() {}
    public func sample() throws -> ThermalPressure {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .moderate
        case .serious: .heavy
        case .critical: .critical
        @unknown default: .nominal
        }
    }
}
