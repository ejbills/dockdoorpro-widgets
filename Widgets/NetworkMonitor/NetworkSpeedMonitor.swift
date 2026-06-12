import Darwin
import Foundation

@Observable
final class NetworkSpeedMonitor {
    var downloadSpeed: Double = 0
    var uploadSpeed: Double = 0

    var downloadHistory: [Double] = Array(repeating: 0, count: 60)
    var uploadHistory: [Double] = Array(repeating: 0, count: 60)

    var sessionTotalDownload: UInt64 = 0
    var sessionTotalUpload: UInt64 = 0

    var availableInterfaces: [String] = []
    var interfaceIPs: [String: String] = [:]

    var selectedInterfaces: Set<String> = [] {
        didSet {
            let snap = Self.fullSnapshot()
            let s = Self.stats(from: snap, for: selectedInterfaces)
            sessionStartIn = s.bytesIn
            sessionStartOut = s.bytesOut
            lastBytesIn = s.bytesIn
            lastBytesOut = s.bytesOut
        }
    }

    var localIP: String {
        if selectedInterfaces.isEmpty { return interfaceIPs.values.first ?? "\u{2014}" }
        return selectedInterfaces.compactMap { interfaceIPs[$0] }.joined(separator: ", ")
    }

    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var sessionStartIn: UInt64 = 0
    private var sessionStartOut: UInt64 = 0
    private var lastTickDate: Date?

    init() {
        let snap = Self.fullSnapshot()
        availableInterfaces = snap.map(\.name)
        interfaceIPs = Dictionary(uniqueKeysWithValues: snap.compactMap { e -> (String, String)? in
            guard !e.ip.isEmpty else { return nil }; return (e.name, e.ip)
        })
        let total = Self.stats(from: snap, for: [])
        lastBytesIn = total.bytesIn
        lastBytesOut = total.bytesOut
        sessionStartIn = total.bytesIn
        sessionStartOut = total.bytesOut
    }

    func tick() {
        let now = Date()
        if let last = lastTickDate, now.timeIntervalSince(last) < 0.5 { return }
        lastTickDate = now

        let snap = Self.fullSnapshot()
        let s = Self.stats(from: snap, for: selectedInterfaces)

        let dl = s.bytesIn >= lastBytesIn ? Double(s.bytesIn - lastBytesIn) : 0
        let ul = s.bytesOut >= lastBytesOut ? Double(s.bytesOut - lastBytesOut) : 0

        downloadSpeed = dl
        uploadSpeed = ul

        downloadHistory.append(dl)
        if downloadHistory.count > 60 { downloadHistory.removeFirst() }
        uploadHistory.append(ul)
        if uploadHistory.count > 60 { uploadHistory.removeFirst() }

        sessionTotalDownload = s.bytesIn >= sessionStartIn ? s.bytesIn - sessionStartIn : 0
        sessionTotalUpload = s.bytesOut >= sessionStartOut ? s.bytesOut - sessionStartOut : 0

        let names = snap.map(\.name)
        if names != availableInterfaces { availableInterfaces = names }
        let ips = Dictionary(uniqueKeysWithValues: snap.compactMap { e -> (String, String)? in
            guard !e.ip.isEmpty else { return nil }; return (e.name, e.ip)
        })
        if ips != interfaceIPs { interfaceIPs = ips }

        lastBytesIn = s.bytesIn
        lastBytesOut = s.bytesOut
    }

    struct IfaceEntry: Equatable {
        var name: String
        var bytesIn: UInt64
        var bytesOut: UInt64
        var ip: String
    }

    private static let skipPrefixes = ["lo", "utun", "bridge", "vmnet", "llw", "awdl", "ipsec", "gif", "stf", "XHC"]

    static func fullSnapshot() -> [IfaceEntry] {
        var entries: [String: IfaceEntry] = [:]

        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let head = ifap else { return [] }
        defer { freeifaddrs(ifap) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let ptr = cursor {
            let ifa = ptr.pointee
            let name = String(cString: ifa.ifa_name)
            cursor = ifa.ifa_next

            guard !skipPrefixes.contains(where: { name.hasPrefix($0) }) else { continue }

            let family = ifa.ifa_addr?.pointee.sa_family ?? 0

            if family == UInt8(AF_LINK), let dataPtr = ifa.ifa_data {
                let d = dataPtr.assumingMemoryBound(to: if_data.self).pointee
                var e = entries[name] ?? IfaceEntry(name: name, bytesIn: 0, bytesOut: 0, ip: "")
                e.bytesIn = UInt64(d.ifi_ibytes)
                e.bytesOut = UInt64(d.ifi_obytes)
                entries[name] = e
            }

            if family == UInt8(AF_INET), let sa = ifa.ifa_addr {
                var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(sa, socklen_t(sa.pointee.sa_len), &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST)
                var e = entries[name] ?? IfaceEntry(name: name, bytesIn: 0, bytesOut: 0, ip: "")
                e.ip = String(cString: buf)
                entries[name] = e
            }
        }
        return entries.values.sorted {
            if $0.ip.isEmpty != $1.ip.isEmpty { return !$0.ip.isEmpty }
            return $0.name < $1.name
        }
    }

    private static func stats(from snap: [IfaceEntry], for selected: Set<String>) -> (bytesIn: UInt64, bytesOut: UInt64) {
        if selected.isEmpty {
            return snap.reduce((UInt64(0), UInt64(0))) { ($0.0 + $1.bytesIn, $0.1 + $1.bytesOut) }
        }
        return snap
            .filter { selected.contains($0.name) }
            .reduce((UInt64(0), UInt64(0))) { ($0.0 + $1.bytesIn, $0.1 + $1.bytesOut) }
    }

    func formattedSpeed(_ bps: Double, unit: String) -> (value: String, unit: String) {
        switch unit {
        case "MB/s": return (String(format: "%.2f", bps / 1_048_576), "MB/s")
        case "KB/s": return (String(format: "%.1f", bps / 1_024), "KB/s")
        default:
            if bps >= 1_048_576 { return (String(format: "%.2f", bps / 1_048_576), "MB/s") }
            if bps >= 1_024 { return (String(format: "%.1f", bps / 1_024), "KB/s") }
            return ("0.0", "KB/s")
        }
    }

    func formattedBytes(_ b: UInt64) -> String {
        let d = Double(b)
        if d >= 1_073_741_824 { return String(format: "%.2f GB", d / 1_073_741_824) }
        if d >= 1_048_576 { return String(format: "%.1f MB", d / 1_048_576) }
        if d >= 1_024 { return String(format: "%.0f KB", d / 1_024) }
        return "\(b) B"
    }
}
