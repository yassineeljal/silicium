import Foundation
import SiliciumShared
import Darwin

/// Top processus via libproc (`proc_pid_rusage`), sans droits administrateur.
public final class ProcessSampler: Sampler {
    public typealias Reading = [ProcessUsage]

    private struct Prev { var cpuNs: UInt64; var diskBytes: UInt64; var energyNj: UInt64 }
    private var previous: [Int32: Prev] = [:]
    private var lastTime: Double = 0
    private let timebase: (numer: UInt64, denom: UInt64)
    private let limit: Int

    public init(limit: Int = 8) {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        timebase = (UInt64(tb.numer), UInt64(tb.denom))
        self.limit = limit
    }

    private func name(of pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 1024)
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0 {
            let path = String(cString: buf)
            // Remonte au .app englobant quand il existe, pour un nom lisible.
            if let r = path.range(of: ".app/") {
                let app = path[..<r.lowerBound]
                return String(app.split(separator: "/").last ?? Substring(path))
            }
            return (path as NSString).lastPathComponent
        }
        var nameBuf = [CChar](repeating: 0, count: 64)
        proc_name(pid, &nameBuf, 64)
        return String(cString: nameBuf)
    }

    public func sample() throws -> [ProcessUsage] {
        let now = monotonicSeconds()
        let dt = lastTime > 0 ? now - lastTime : 0
        let bytesNeeded = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytesNeeded > 0 else { throw SamplerError.unavailable("proc_listpids") }
        var pids = [Int32](repeating: 0, count: Int(bytesNeeded) / MemoryLayout<Int32>.size + 32)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        let n = Int(got) / MemoryLayout<Int32>.size

        var current: [Int32: Prev] = [:]
        var rows: [(pid: Int32, cpu: Double, mem: UInt64, disk: Double, energy: Double)] = []
        for i in 0..<n {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var ru = rusage_info_v6()
            let ok = withUnsafeMutablePointer(to: &ru) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
            }
            guard ok == 0 else { continue }
            let cpuNs = (ru.ri_user_time &+ ru.ri_system_time) &* timebase.numer / timebase.denom
            let disk = ru.ri_diskio_bytesread &+ ru.ri_diskio_byteswritten
            let energy = ru.ri_energy_nj
            current[pid] = Prev(cpuNs: cpuNs, diskBytes: disk, energyNj: energy)
            if dt > 0, let p = previous[pid] {
                let dCpu = cpuNs >= p.cpuNs ? Double(cpuNs - p.cpuNs) : 0
                let cpuPct = dCpu / (dt * 1e9) * 100
                let dDisk = disk >= p.diskBytes ? Double(disk - p.diskBytes) / dt : 0
                let dEn = energy >= p.energyNj ? Double(energy - p.energyNj) / dt / 1e9 : 0   // W
                rows.append((pid, cpuPct, ru.ri_phys_footprint, dDisk, dEn))
            }
        }
        previous = current
        lastTime = now

        // Fusionne par nom (plusieurs processus d'une même app), puis garde les plus actifs.
        var byName: [String: ProcessUsage] = [:]
        for r in rows where r.cpu > 0.1 || r.mem > 200_000_000 || r.disk > 1000 {
            let nm = name(of: r.pid)
            if var u = byName[nm] {
                u.cpuPercent += r.cpu; u.memoryBytes += r.mem
                u.diskBytesPerSec += r.disk; u.energyScore += r.energy
                byName[nm] = u
            } else {
                byName[nm] = ProcessUsage(pid: r.pid, name: nm, cpuPercent: r.cpu, memoryBytes: r.mem,
                                          diskBytesPerSec: r.disk, energyScore: r.energy)
            }
        }
        return byName.values.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(max(limit, 30)).map { $0 }
    }
}
