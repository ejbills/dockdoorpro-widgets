import Foundation

enum VolumeKind {
    case internalDrive
    case external
    case removable
    case network

    var symbolName: String {
        switch self {
        case .internalDrive: return "internaldrive"
        case .external: return "externaldrive"
        case .removable: return "sdcard"
        case .network: return "externaldrive.connected.to.line.below"
        }
    }
}

struct VolumeInfo: Identifiable {
    let id: String
    let url: URL
    let name: String
    let totalBytes: Int64
    let freeBytes: Int64
    let isInternal: Bool
    let isRemovable: Bool
    let isEjectable: Bool
    let isLocal: Bool

    var kind: VolumeKind {
        if !isLocal { return .network }
        if isInternal { return .internalDrive }
        if isRemovable { return .removable }
        return .external
    }

    var canEject: Bool {
        isEjectable && !isInternal
    }

    var totalGB: Double { Double(totalBytes) / 1_000_000_000 }
    var freeGB: Double { Double(freeBytes) / 1_000_000_000 }
    var usedGB: Double { max(totalGB - freeGB, 0) }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(totalBytes - freeBytes) / Double(totalBytes)))
    }

    var freeFraction: Double {
        1 - usedFraction
    }

    var freeLabel: String { formatGB(freeGB) + " free" }
    var usedLabel: String { formatGB(usedGB) }
    var totalLabel: String { formatGB(totalGB) }

    private func formatGB(_ gb: Double) -> String {
        if gb >= 100 { return "\(Int(gb)) GB" }
        return String(format: "%.1f GB", gb)
    }
}

enum StorageVolumeSnapshot {
    static func rootVolume() -> VolumeInfo? {
        volumeInfo(for: URL(fileURLWithPath: "/"))
    }

    static func mountedVolumes() -> [VolumeInfo] {
        let keys = Array(resourceKeys)
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap(volumeInfo(for:))
            .sorted { lhs, rhs in
                if lhs.id == "/" { return true }
                if rhs.id == "/" { return false }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .volumeAvailableCapacityForImportantUsageKey,
        .volumeAvailableCapacityKey,
        .volumeIsEjectableKey,
        .volumeIsInternalKey,
        .volumeIsLocalKey,
        .volumeIsRemovableKey,
        .volumeLocalizedNameKey,
        .volumeNameKey,
        .volumeTotalCapacityKey,
    ]

    private static func volumeInfo(for url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: resourceKeys),
              let total = values.volumeTotalCapacity,
              total > 0
        else { return nil }

        let importantUsage = values.volumeAvailableCapacityForImportantUsage ?? 0
        let free = importantUsage > 0
            ? importantUsage
            : Int64(values.volumeAvailableCapacity ?? 0)
        let name = values.volumeLocalizedName
            ?? values.volumeName
            ?? FileManager.default.displayName(atPath: url.path)

        return VolumeInfo(
            id: url.path,
            url: url,
            name: name,
            totalBytes: Int64(total),
            freeBytes: max(free, 0),
            isInternal: values.volumeIsInternal ?? false,
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isLocal: values.volumeIsLocal ?? true
        )
    }
}
