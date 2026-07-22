import AppKit
import Darwin
import Foundation

struct ProcessIdentity: Equatable {
    let pid: pid_t
    let ownerUID: uid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

struct ProcessMetric: Identifiable, Equatable {
    let pid: pid_t
    let name: String
    let value: Double
    let identity: ProcessIdentity?

    var id: String {
        guard let identity else { return "\(pid):unknown" }
        return "\(pid):\(identity.startSeconds):\(identity.startMicroseconds)"
    }

    var canTerminate: Bool {
        guard let identity, pid > 1, pid != getpid() else { return false }
        return identity.ownerUID == getuid() || identity.ownerUID == geteuid()
    }
}

enum ProcessTerminationResult: Equatable {
    case requested
    case forceRequested
    case blocked
    case permissionDenied
    case processChanged
    case notRunning
    case failed(Int32)

    var displayText: String {
        switch self {
        case .requested: return "Requested"
        case .forceRequested: return "Killed"
        case .blocked: return "Protected"
        case .permissionDenied: return "Denied"
        case .processChanged: return "PID changed"
        case .notRunning: return "Exited"
        case .failed: return "Failed"
        }
    }
}

struct CPUUsageSnapshot {
    var user: Double = 0
    var system: Double = 0
    var idle: Double = 1

    var used: Double { min(max(user + system, 0), 1) }
}

struct MemoryUsageSnapshot {
    var total: Double = 0
    var used: Double = 0
    var app: Double = 0
    var wired: Double = 0
    var compressed: Double = 0
    var available: Double = 0
    var cached: Double = 0
    var swapUsed: Double = 0
    var pressure: MemoryPressure = .normal

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(max(used / total, 0), 1)
    }
}

enum MemoryPressure: String {
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"
}

@Observable
final class SystemMetricsMonitor {
    private(set) var cpu = CPUUsageSnapshot()
    private(set) var memory = MemoryUsageSnapshot()
    private(set) var cpuHistory: [Double] = Array(repeating: 0, count: 60)
    private(set) var memoryHistory: [Double] = Array(repeating: 0, count: 60)
    private(set) var topCPUProcesses: [ProcessMetric] = []
    private(set) var topMemoryProcesses: [ProcessMetric] = []
    private(set) var loadAverages: [Double] = [0, 0, 0]
    private(set) var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    private(set) var cpuFrequencyMHz: Double?
    private(set) var cpuTemperature: Double?

    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
    }

    private struct ProcessSnapshot {
        let pid: pid_t
        let cpuTimeNanoseconds: UInt64
        let residentBytes: UInt64
    }

    private var previousCPUTicks: CPUTicks?
    private var previousProcessTimes: [pid_t: UInt64] = [:]
    private var previousProcessDate = Date()
    private var lastTickDate = Date()
    private let hardwareMonitor = SystemHardwareMonitor()

    init() {
        previousCPUTicks = Self.readCPUTicks()
        memory = Self.readMemory()

        let processes = Self.readProcesses()
        previousProcessTimes = Dictionary(
            uniqueKeysWithValues: processes.map { ($0.pid, $0.cpuTimeNanoseconds) }
        )
        topMemoryProcesses = Self.memoryProcessMetrics(from: processes)
        loadAverages = Self.readLoadAverages()
        cpuTemperature = hardwareMonitor.readTemperature()
        cpuFrequencyMHz = hardwareMonitor.readFrequencyMHz()
    }

    func tick(minimumInterval: TimeInterval = 0.75) {
        let now = Date()
        guard now.timeIntervalSince(lastTickDate) >= minimumInterval else { return }
        lastTickDate = now

        refreshCPU()
        memory = Self.readMemory()
        refreshProcesses(at: now)
        loadAverages = Self.readLoadAverages()
        uptime = ProcessInfo.processInfo.systemUptime
        cpuTemperature = hardwareMonitor.readTemperature()
        cpuFrequencyMHz = hardwareMonitor.readFrequencyMHz()

        append(cpu.used, to: &cpuHistory)
        append(memory.usedFraction, to: &memoryHistory)
    }

    private func refreshCPU() {
        guard let current = Self.readCPUTicks() else { return }
        defer { previousCPUTicks = current }
        guard let previous = previousCPUTicks else { return }

        let userDelta = Double(current.user &- previous.user)
        let systemDelta = Double(current.system &- previous.system)
        let idleDelta = Double(current.idle &- previous.idle)
        let niceDelta = Double(current.nice &- previous.nice)
        let total = userDelta + systemDelta + idleDelta + niceDelta
        guard total > 0 else { return }

        let user = (userDelta + niceDelta) / total
        let system = systemDelta / total
        cpu = CPUUsageSnapshot(
            user: user.isFinite ? user : 0,
            system: system.isFinite ? system : 0,
            idle: idleDelta.isFinite ? idleDelta / total : 1
        )
    }

    private func refreshProcesses(at now: Date) {
        let snapshots = Self.readProcesses()
        let elapsed = now.timeIntervalSince(previousProcessDate)
        previousProcessDate = now

        if elapsed > 0 {
            let elapsedNanoseconds = elapsed * 1_000_000_000
            let candidates = snapshots.compactMap { process -> (pid: pid_t, value: Double)? in
                guard let previous = previousProcessTimes[process.pid],
                      process.cpuTimeNanoseconds >= previous
                else { return nil }

                let delta = Double(process.cpuTimeNanoseconds - previous)
                let percent = delta / elapsedNanoseconds * 100
                guard percent.isFinite, percent >= 0.05 else { return nil }
                return (process.pid, percent)
            }

            topCPUProcesses = candidates
                .sorted { $0.value > $1.value }
                .prefix(12)
                .map { Self.processMetric(pid: $0.pid, value: $0.value) }
        }

        previousProcessTimes = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.pid, $0.cpuTimeNanoseconds) }
        )
        topMemoryProcesses = Self.memoryProcessMetrics(from: snapshots)
    }

    func requestTermination(of process: ProcessMetric, force: Bool) -> ProcessTerminationResult {
        guard process.canTerminate, let expectedIdentity = process.identity else {
            return .blocked
        }
        guard let currentIdentity = Self.processIdentity(for: process.pid) else {
            return .notRunning
        }
        guard currentIdentity == expectedIdentity else {
            return .processChanged
        }

        if !force,
           let application = NSRunningApplication(processIdentifier: process.pid),
           application.terminate() {
            return .requested
        }

        errno = 0
        let signal = force ? SIGKILL : SIGTERM
        if Darwin.kill(process.pid, signal) == 0 {
            return force ? .forceRequested : .requested
        }

        switch errno {
        case EPERM: return .permissionDenied
        case ESRCH: return .notRunning
        default: return .failed(errno)
        }
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }

    private static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        return CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private static func readMemory() -> MemoryUsageSnapshot {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemoryUsageSnapshot() }

        let pageSize = Double(vm_page_size)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let active = Double(stats.active_count) * pageSize
        let inactive = Double(stats.inactive_count) * pageSize
        let speculative = Double(stats.speculative_count) * pageSize
        let wired = Double(stats.wire_count) * pageSize
        let compressed = Double(stats.compressor_page_count) * pageSize
        let purgeable = Double(stats.purgeable_count) * pageSize
        let external = Double(stats.external_page_count) * pageSize

        // This matches the public Stats app's memory accounting formula.
        let calculatedUsed = active + inactive + speculative + wired + compressed - purgeable - external
        let used = min(max(calculatedUsed, 0), total)
        let app = max(used - wired - compressed, 0)

        var pressureLevel: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.stride
        sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &pressureSize, nil, 0)

        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.stride
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)

        let pressure: MemoryPressure
        switch pressureLevel {
        case 2: pressure = .warning
        case 4: pressure = .critical
        default: pressure = .normal
        }

        return MemoryUsageSnapshot(
            total: total,
            used: used,
            app: app,
            wired: wired,
            compressed: compressed,
            available: max(total - used, 0),
            cached: max(purgeable + external, 0),
            swapUsed: Double(swap.xsu_used),
            pressure: pressure
        )
    }

    private static func readProcesses() -> [ProcessSnapshot] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let bytes = pids.withUnsafeMutableBytes { buffer -> Int32 in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buffer.baseAddress,
                Int32(buffer.count)
            )
        }
        guard bytes > 0 else { return [] }

        let count = Int(bytes) / MemoryLayout<pid_t>.stride
        return pids.prefix(count).compactMap { pid in
            guard pid > 0 else { return nil }
            var info = proc_taskinfo()
            let expectedSize = MemoryLayout<proc_taskinfo>.stride
            let copied = withUnsafeMutablePointer(to: &info) { pointer in
                proc_pidinfo(pid, PROC_PIDTASKINFO, 0, pointer, Int32(expectedSize))
            }
            guard copied == expectedSize else { return nil }

            return ProcessSnapshot(
                pid: pid,
                cpuTimeNanoseconds: info.pti_total_user &+ info.pti_total_system,
                residentBytes: info.pti_resident_size
            )
        }
    }

    private static func memoryProcessMetrics(from snapshots: [ProcessSnapshot]) -> [ProcessMetric] {
        snapshots
            .filter { $0.residentBytes > 0 }
            .sorted { $0.residentBytes > $1.residentBytes }
            .prefix(12)
            .map { processMetric(pid: $0.pid, value: Double($0.residentBytes)) }
    }

    private static func processMetric(pid: pid_t, value: Double) -> ProcessMetric {
        ProcessMetric(
            pid: pid,
            name: processName(for: pid),
            value: value,
            identity: processIdentity(for: pid)
        )
    }

    static func processIdentity(for pid: pid_t) -> ProcessIdentity? {
        guard pid > 0 else { return nil }
        var info = proc_bsdinfo()
        let expectedSize = MemoryLayout<proc_bsdinfo>.stride
        let copied = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, Int32(expectedSize))
        }
        guard copied == expectedSize, info.pbi_pid == UInt32(pid) else { return nil }

        return ProcessIdentity(
            pid: pid,
            ownerUID: info.pbi_uid,
            startSeconds: info.pbi_start_tvsec,
            startMicroseconds: info.pbi_start_tvusec
        )
    }

    private static func processName(for pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid),
           let localizedName = app.localizedName,
           !localizedName.isEmpty {
            return localizedName
        }

        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = buffer.withUnsafeMutableBufferPointer {
            proc_name(pid, $0.baseAddress, UInt32($0.count))
        }
        if length > 0 {
            return String(cString: buffer)
        }
        return "Process \(pid)"
    }

    private static func readLoadAverages() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        let readCount = values.withUnsafeMutableBufferPointer {
            getloadavg($0.baseAddress, Int32($0.count))
        }
        return readCount == 3 ? values : [0, 0, 0]
    }
}
