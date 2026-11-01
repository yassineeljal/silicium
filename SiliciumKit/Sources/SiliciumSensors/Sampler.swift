import Foundation

/// Un sampler lit une source de données. Les samplers à état (deltas) sont des classes
/// possédées par un seul acteur (`SensorHub`) : ils ne sont jamais partagés.
public protocol Sampler: AnyObject {
    associatedtype Reading: Sendable
    func sample() throws -> Reading
}

public enum SamplerError: Error, Sendable {
    case unavailable(String)
}

/// Horloge monotone en secondes.
@inline(__always) func monotonicSeconds() -> Double {
    Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
}
