import Foundation
import SiliciumShared
import CoreWLAN
import Darwin

/// Débit réseau (getifaddrs) + signal Wi-Fi (CoreWLAN).
public final class NetworkSampler: Sampler {
    public typealias Reading = NetworkReading
    private var last: (date: Double, rx: UInt64, tx: UInt64)?

    public init() {}

    private func counters() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ptr) == 0, let first = ptr else { return (0, 0) }
        defer { freeifaddrs(ptr) }
        var cur: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cur {
            let name = String(cString: p.pointee.ifa_name)
            if p.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), name.hasPrefix("en"),
               let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self) {
                rx += UInt64(data.pointee.ifi_ibytes)
                tx += UInt64(data.pointee.ifi_obytes)
            }
            cur = p.pointee.ifa_next
        }
        return (rx, tx)
    }

    public func sample() throws -> NetworkReading {
        let now = monotonicSeconds()
        let c = counters()
        var down = 0.0, up = 0.0
        if let l = last, now > l.date {
            let dt = now - l.date
            down = c.rx >= l.rx ? Double(c.rx - l.rx) / dt : 0
            up = c.tx >= l.tx ? Double(c.tx - l.tx) / dt : 0
        }
        last = (now, c.rx, c.tx)

        var reading = NetworkReading(downBytesPerSec: down, upBytesPerSec: up)
        if let iface = CWWiFiClient.shared().interface(), iface.powerOn() {
            let rssi = iface.rssiValue()
            if rssi != 0 {
                reading.wifiConnected = true
                reading.rssi = rssi
                reading.noise = iface.noiseMeasurement()
                reading.linkRateMbps = iface.transmitRate()
            }
        }
        return reading
    }
}
