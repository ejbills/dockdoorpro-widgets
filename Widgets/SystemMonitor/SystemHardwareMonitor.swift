import CoreFoundation
import Darwin
import Foundation
import IOKit

#if arch(arm64)
@_silgen_name("IOReportCopyChannelsInGroup")
private func IOReportCopyChannelsInGroup(
    _ group: CFString?,
    _ subgroup: CFString?,
    _ channelID: UInt64,
    _ options: UInt64,
    _ flags: UInt64
) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportMergeChannels")
private func IOReportMergeChannels(
    _ destination: CFDictionary,
    _ source: CFDictionary,
    _ options: CFTypeRef?
)

@_silgen_name("IOReportCreateSubscription")
private func IOReportCreateSubscription(
    _ allocator: UnsafeMutableRawPointer?,
    _ channels: CFMutableDictionary,
    _ subscribedChannels: UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>?,
    _ options: UInt64,
    _ context: CFTypeRef?
) -> OpaquePointer?

@_silgen_name("IOReportCreateSamples")
private func IOReportCreateSamples(
    _ subscription: OpaquePointer?,
    _ channels: CFMutableDictionary,
    _ context: CFTypeRef?
) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportCreateSamplesDelta")
private func IOReportCreateSamplesDelta(
    _ previous: CFDictionary,
    _ current: CFDictionary,
    _ context: CFTypeRef?
) -> Unmanaged<CFDictionary>?

@_silgen_name("IOReportChannelGetGroup")
private func IOReportChannelGetGroup(_ channel: CFDictionary) -> Unmanaged<CFString>?

@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ channel: CFDictionary) -> Unmanaged<CFString>?

@_silgen_name("IOReportStateGetCount")
private func IOReportStateGetCount(_ channel: CFDictionary) -> Int32

@_silgen_name("IOReportStateGetNameForIndex")
private func IOReportStateGetNameForIndex(
    _ channel: CFDictionary,
    _ index: Int32
) -> Unmanaged<CFString>?

@_silgen_name("IOReportStateGetResidency")
private func IOReportStateGetResidency(_ channel: CFDictionary, _ index: Int32) -> Int64
#endif

/// Reads the two hardware values shown in CPU Details.
///
/// Temperature comes from AppleSMC. On Apple Silicon, frequency is calculated
/// from IOReport performance-state residency over the widget refresh interval,
/// matching the approach used by full system-monitoring applications.
final class SystemHardwareMonitor {
    private let temperatureReader = AppleSMCTemperatureReader()

    #if arch(arm64)
    private let frequencyReader = AppleSiliconFrequencyReader()
    #endif

    func readTemperature() -> Double? {
        temperatureReader?.readCPU()
    }

    func readFrequencyMHz() -> Double? {
        #if arch(arm64)
        return frequencyReader?.readMHz()
        #else
        var value: UInt64 = 0
        var size = MemoryLayout<UInt64>.stride
        guard sysctlbyname("hw.cpufrequency", &value, &size, nil, 0) == 0, value > 0 else {
            return nil
        }
        return Double(value) / 1_000_000
        #endif
    }
}

private final class AppleSMCTemperatureReader {
    private typealias SMCBytes = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    private struct SMCKeyData {
        struct Version {
            var major: UInt8 = 0
            var minor: UInt8 = 0
            var build: UInt8 = 0
            var reserved: UInt8 = 0
            var release: UInt16 = 0
        }

        struct PowerLimit {
            var version: UInt16 = 0
            var length: UInt16 = 0
            var cpu: UInt32 = 0
            var gpu: UInt32 = 0
            var memory: UInt32 = 0
        }

        struct KeyInfo {
            var dataSize: UInt32 = 0
            var dataType: UInt32 = 0
            var attributes: UInt8 = 0
        }

        var key: UInt32 = 0
        var version = Version()
        var powerLimit = PowerLimit()
        var keyInfo = KeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: SMCBytes = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    private var connection: io_connect_t = 0
    private let sensorKeys: [String]

    init?() {
        sensorKeys = Self.platformSensorKeys()

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC"),
            &iterator
        ) == kIOReturnSuccess else { return nil }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == kIOReturnSuccess else {
            return nil
        }
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func readCPU() -> Double? {
        for key in ["TC0D", "TC0E", "TC0F", "TC0P", "TC0H"] {
            if let value = value(for: key), Self.isSaneTemperature(value) {
                return value
            }
        }

        let values = sensorKeys.compactMap { key -> Double? in
            guard let value = value(for: key), Self.isSaneTemperature(value) else { return nil }
            return value
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func value(for key: String) -> Double? {
        guard key.utf8.count == 4 else { return nil }

        var input = SMCKeyData()
        var output = SMCKeyData()
        input.key = Self.fourCharacterCode(key)
        input.data8 = 9 // readKeyInfo

        guard call(input: &input, output: &output) == kIOReturnSuccess,
              output.keyInfo.dataSize > 0
        else { return nil }

        let dataSize = Int(output.keyInfo.dataSize)
        let dataType = Self.string(from: output.keyInfo.dataType)

        input = SMCKeyData()
        input.key = Self.fourCharacterCode(key)
        input.keyInfo.dataSize = output.keyInfo.dataSize
        input.data8 = 5 // readBytes
        output = SMCKeyData()

        guard call(input: &input, output: &output) == kIOReturnSuccess else { return nil }

        let bytes = withUnsafeBytes(of: output.bytes) { rawBuffer in
            Array(rawBuffer.prefix(min(dataSize, rawBuffer.count)))
        }
        guard bytes.contains(where: { $0 != 0 }) else { return nil }

        switch dataType {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            var value: Float = 0
            withUnsafeMutableBytes(of: &value) { destination in
                destination.copyBytes(from: bytes.prefix(4))
            }
            return Double(value)
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double((Int(bytes[0]) << 6) | (Int(bytes[1]) >> 2))
        case "ui8 ":
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        default:
            return nil
        }
    }

    private func call(input: inout SMCKeyData, output: inout SMCKeyData) -> kern_return_t {
        var outputSize = MemoryLayout<SMCKeyData>.stride
        return IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<SMCKeyData>.stride,
            &output,
            &outputSize
        )
    }

    private static func platformSensorKeys() -> [String] {
        let name = cpuBrandString()
        if name.contains("M5") {
            return [
                "Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
                "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d",
                "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y",
            ]
        }
        if name.contains("M4") {
            return [
                "Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05",
                "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
            ]
        }
        if name.contains("M3") {
            return [
                "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09",
                "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49",
                "Tf4A", "Tf4B", "Tf4D", "Tf4E",
            ]
        }
        if name.contains("M2") {
            return [
                "Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05",
                "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j",
            ]
        }
        if name.contains("M1") {
            return [
                "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H",
                "Tp0L", "Tp0P", "Tp0X", "Tp0b",
            ]
        }
        return []
    }

    fileprivate static func cpuBrandString() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: buffer)
    }

    private static func isSaneTemperature(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value < 110
    }

    private static func fourCharacterCode(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func string(from code: UInt32) -> String {
        String(bytes: [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ], encoding: .ascii) ?? ""
    }
}

#if arch(arm64)
private final class AppleSiliconFrequencyReader {
    private struct Profile {
        let efficiency: [Double]
        let performance: [Double]
        let superCores: [Double]
        let efficiencyCount: Double
        let performanceCount: Double
        let superCoreCount: Double
    }

    private let profile: Profile
    private let channels: CFMutableDictionary
    private let subscription: OpaquePointer
    private var previousSample: CFDictionary?

    init?() {
        guard let profile = Self.readProfile(),
              (!profile.efficiency.isEmpty || !profile.performance.isEmpty || !profile.superCores.isEmpty),
              let channels = Self.makeChannels()
        else { return nil }

        var subscribedChannels: Unmanaged<CFMutableDictionary>?
        guard let subscription = IOReportCreateSubscription(
            nil,
            channels,
            &subscribedChannels,
            0,
            nil
        ) else { return nil }
        subscribedChannels?.release()

        self.profile = profile
        self.channels = channels
        self.subscription = subscription
        self.previousSample = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue()
    }

    func readMHz() -> Double? {
        guard let current = IOReportCreateSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return nil
        }
        guard let previous = previousSample else {
            previousSample = current
            return nil
        }
        previousSample = current

        guard let delta = IOReportCreateSamplesDelta(previous, current, nil)?.takeRetainedValue() else {
            return nil
        }

        var efficiencyValues: [Double] = []
        var performanceValues: [Double] = []
        var superCoreValues: [Double] = []

        for channel in Self.channelDictionaries(in: delta) {
            let group = IOReportChannelGetGroup(channel)?.takeUnretainedValue() as String? ?? ""
            guard group == "CPU Stats" else { continue }

            let name = IOReportChannelGetChannelName(channel)?.takeUnretainedValue() as String? ?? ""
            if name.contains("ECPU"),
               let value = Self.frequency(for: channel, states: profile.efficiency) {
                efficiencyValues.append(value)
            } else if name.contains(profile.superCores.isEmpty ? "PCPU" : "MCPU"),
                      let value = Self.frequency(for: channel, states: profile.performance) {
                performanceValues.append(value)
            } else if !profile.superCores.isEmpty,
                      name.contains("PCPU"),
                      let value = Self.frequency(for: channel, states: profile.superCores) {
                superCoreValues.append(value)
            }
        }

        let efficiency = Self.average(efficiencyValues)
        let performance = Self.average(performanceValues)
        let superCores = Self.average(superCoreValues)

        var weightedTotal = 0.0
        var activeCoreCount = 0.0
        if let efficiency, profile.efficiencyCount > 0 {
            weightedTotal += efficiency * profile.efficiencyCount
            activeCoreCount += profile.efficiencyCount
        }
        if let performance, profile.performanceCount > 0 {
            weightedTotal += performance * profile.performanceCount
            activeCoreCount += profile.performanceCount
        }
        if let superCores, profile.superCoreCount > 0 {
            weightedTotal += superCores * profile.superCoreCount
            activeCoreCount += profile.superCoreCount
        }

        if activeCoreCount > 0 {
            return weightedTotal / activeCoreCount
        }
        return Self.average([efficiency, performance, superCores].compactMap { $0 })
    }

    private static func makeChannels() -> CFMutableDictionary? {
        let subgroups = ["CPU Complex Performance States", "CPU Core Performance States"]
        let sourceChannels = subgroups.compactMap {
            IOReportCopyChannelsInGroup("CPU Stats" as CFString, $0 as CFString, 0, 0, 0)?.takeRetainedValue()
        }
        guard let first = sourceChannels.first else { return nil }

        for channel in sourceChannels.dropFirst() {
            IOReportMergeChannels(first, channel, nil)
        }
        return CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, first)
    }

    private static func channelDictionaries(in sample: CFDictionary) -> [CFDictionary] {
        guard let dictionary = sample as? [String: Any],
              let channels = dictionary["IOReportChannels"] as? NSArray
        else { return [] }

        let array = channels as CFArray
        return (0..<CFArrayGetCount(array)).map { index in
            unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: CFDictionary.self)
        }
    }

    private static func frequency(for channel: CFDictionary, states: [Double]) -> Double? {
        guard !states.isEmpty else { return nil }

        let count = Int(IOReportStateGetCount(channel))
        guard count > 0 else { return nil }

        var residencies: [(name: String, value: Int64)] = []
        residencies.reserveCapacity(count)
        for index in 0..<count {
            let name = IOReportStateGetNameForIndex(channel, Int32(index))?
                .takeUnretainedValue() as String? ?? ""
            residencies.append((name, IOReportStateGetResidency(channel, Int32(index))))
        }

        guard let activeOffset = residencies.firstIndex(where: {
            $0.name != "IDLE" && $0.name != "DOWN" && $0.name != "OFF"
        }) else { return nil }

        let activeResidency = residencies.dropFirst(activeOffset).reduce(0.0) {
            $0 + Double(max($1.value, 0))
        }
        guard activeResidency > 0 else { return nil }

        var value = 0.0
        for stateIndex in states.indices {
            let residencyIndex = activeOffset + stateIndex
            guard residencies.indices.contains(residencyIndex) else { break }
            let share = Double(max(residencies[residencyIndex].value, 0)) / activeResidency
            value += share * states[stateIndex]
        }

        guard value.isFinite, value > 0 else { return nil }
        return max(value, states.min() ?? value)
    }

    private static func readProfile() -> Profile? {
        let brand = AppleSMCTemperatureReader.cpuBrandString()
        let generation = [5, 4, 3, 2, 1].first(where: { brand.contains("M\($0)") }) ?? 0
        guard generation > 0 else { return nil }

        let properties = pmgrProperties()
        let counts = cpuCoreCounts()
        let divisor: UInt32 = generation >= 4 ? 1_000 : 1_000_000

        if generation >= 5 {
            return Profile(
                efficiency: frequencies(from: properties["voltage-states1-sram"] as? Data, divisor: divisor),
                performance: frequencies(from: properties["voltage-states22-sram"] as? Data, divisor: divisor),
                superCores: frequencies(from: properties["voltage-states5-sram"] as? Data, divisor: divisor),
                efficiencyCount: counts["e-core-count"] ?? 0,
                performanceCount: counts["m-core-count"] ?? 0,
                superCoreCount: counts["p-core-count"] ?? 0
            )
        }

        return Profile(
            efficiency: frequencies(from: properties["voltage-states1-sram"] as? Data, divisor: divisor),
            performance: frequencies(from: properties["voltage-states5-sram"] as? Data, divisor: divisor),
            superCores: [],
            efficiencyCount: counts["e-core-count"] ?? 0,
            performanceCount: counts["p-core-count"] ?? 0,
            superCoreCount: 0
        )
    }

    private static func pmgrProperties() -> NSDictionary {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("AppleARMIODevice"),
            &iterator
        ) == kIOReturnSuccess else { return [:] }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let namePointer = UnsafeMutablePointer<io_name_t>.allocate(capacity: 1)
            defer { namePointer.deallocate() }
            guard IORegistryEntryGetName(service, namePointer) == kIOReturnSuccess else { continue }
            let name = String(
                cString: UnsafeRawPointer(namePointer).assumingMemoryBound(to: CChar.self)
            )
            guard name == "pmgr" else { continue }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                service,
                &properties,
                kCFAllocatorDefault,
                0
            ) == kIOReturnSuccess else { continue }
            return properties?.takeRetainedValue() as NSDictionary? ?? [:]
        }
        return [:]
    }

    private static func cpuCoreCounts() -> [String: Double] {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        guard entry != 0 else { return [:] }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry,
            &properties,
            kCFAllocatorDefault,
            0
        ) == kIOReturnSuccess,
              let dictionary = properties?.takeRetainedValue() as NSDictionary?
        else { return [:] }

        var result: [String: Double] = [:]
        for key in ["e-core-count", "m-core-count", "p-core-count"] {
            guard let data = dictionary[key] as? Data, data.count >= 4 else { continue }
            let value = data.withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))
            }
            result[key] = Double(value)
        }
        return result
    }

    private static func frequencies(from data: Data?, divisor: UInt32) -> [Double] {
        guard let data, data.count >= 4 else { return [] }
        return stride(from: 0, to: data.count, by: 8).compactMap { offset in
            guard offset + 4 <= data.count else { return nil }
            let raw = data.withUnsafeBytes {
                UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            }
            let mhz = Double(raw / divisor)
            return mhz > 0 ? mhz : nil
        }
    }

    private static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
#endif
