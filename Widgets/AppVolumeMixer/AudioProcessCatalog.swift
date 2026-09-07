import AppKit
import CoreAudio
import Darwin
import Foundation

/// Which app a process is doing work on behalf of, from libsystem. It is the
/// same answer TCC and the App Store use to bill an XPC service's activity to
/// the app that asked for it, and the only one that gets from a WebKit GPU
/// process back to Safari.
@_silgen_name("responsibility_get_pid_responsible_for_pid")
private func responsibility_get_pid_responsible_for_pid(_ pid: pid_t) -> pid_t

/// One row in the mixer: an app plus every audio process object it owns.
struct MixerEntry: Identifiable, Equatable {
    /// Row identity and persistence key: bundle id when the app has one,
    /// otherwise the display name. Pids recycle, so they are never the key.
    let key: String
    let pid: pid_t
    let name: String
    /// True while the app is actually pushing samples right now. Apps stay
    /// listed between sounds as long as they hold an audio connection.
    let isPlaying: Bool
    /// Apps that drive their own audio path (Zoom, DAWs). They get a row so
    /// their absence doesn't read as a bug, but are never tapped.
    let isBypassed: Bool
    let audioObjects: [AudioObjectID]

    var id: String { key }
}

/// Reads the CoreAudio process list and folds it into one row per app.
enum AudioProcessCatalog {
    /// How far up the BSD parent chain to look for the app a helper process
    /// belongs to. Browser renderers report themselves as responsible, so the
    /// parent chain is what leads back to the browser.
    private static let ownerSearchDepth = 4

    private static let bypassedBundlePrefixes = [
        "us.zoom.",
        "com.apple.logic",
        "com.ableton.",
        "com.avid.protools",
        "com.native-instruments.",
        "com.presonus.",
        "com.steinberg.",
    ]

    static func entries(excluding ownPID: pid_t) -> [MixerEntry] {
        var objectsByOwner: [pid_t: [AudioObjectID]] = [:]
        var playingOwners: Set<pid_t> = []
        var bundleByOwner: [pid_t: String] = [:]
        var appByOwner: [pid_t: NSRunningApplication] = [:]

        for object in processObjects() {
            var pid: pid_t = -1
            guard read(object, kAudioProcessPropertyPID, into: &pid), pid > 0, pid != ownPID else { continue }
            guard let owner = owningApp(of: pid) else { continue }
            let ownerPID = owner.processIdentifier
            // The host's own sound is never part of the mixer, whether it
            // comes from the app itself or a helper it is responsible for.
            guard ownerPID != ownPID else { continue }

            var running: UInt32 = 0
            _ = read(object, kAudioProcessPropertyIsRunningOutput, into: &running)
            if running != 0 { playingOwners.insert(ownerPID) }

            objectsByOwner[ownerPID, default: []].append(object)
            appByOwner[ownerPID] = owner
            if bundleByOwner[ownerPID] == nil {
                // The audio object carries its own process's bundle id, which
                // is only the right one when the app plays its own sound. For
                // a helper, the owning app's bundle id is what counts.
                bundleByOwner[ownerPID] = owner.bundleIdentifier
                    ?? (pid == ownerPID ? bundleIdentifier(of: object) : nil)
            }
        }

        var entries: [MixerEntry] = []
        for (ownerPID, objects) in objectsByOwner {
            let app = appByOwner[ownerPID]
            let name = app?.localizedName ?? "pid \(ownerPID)"
            let bundleID = bundleByOwner[ownerPID]
            entries.append(
                MixerEntry(
                    key: bundleID ?? name,
                    pid: ownerPID,
                    name: name,
                    isPlaying: playingOwners.contains(ownerPID),
                    isBypassed: isBypassed(bundleIdentifier: bundleID, name: name),
                    audioObjects: objects.sorted()
                )
            )
        }

        // Two processes of the same unbundled app share a key; merge them so
        // one row owns every object and a single tap covers the app.
        var merged: [String: MixerEntry] = [:]
        for entry in entries {
            guard let existing = merged[entry.key] else {
                merged[entry.key] = entry
                continue
            }
            merged[entry.key] = MixerEntry(
                key: existing.key,
                pid: existing.pid,
                name: existing.name,
                isPlaying: existing.isPlaying || entry.isPlaying,
                isBypassed: existing.isBypassed || entry.isBypassed,
                audioObjects: Array(Set(existing.audioObjects).union(entry.audioObjects)).sorted()
            )
        }

        return merged.values.sorted {
            switch $0.name.localizedCaseInsensitiveCompare($1.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            // Swift's sort is not stable, so identically named apps need an
            // explicit tie-break or their rows swap on every refresh.
            case .orderedSame: $0.key < $1.key
            }
        }
    }

    static func icon(for entry: MixerEntry) -> NSImage? {
        NSRunningApplication(processIdentifier: entry.pid)?.icon
    }

    // MARK: - Process ownership

    /// The regular app a sound belongs to: the process itself when it is one,
    /// otherwise the app it is playing on behalf of.
    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        if let app = regularApp(pid) { return app }

        // Safari, Mail and anything else with a web view play through a
        // WebKit GPU process, which launchd spawns — its parent is pid 1, so
        // the parent chain leads nowhere. Responsibility is what points back
        // at the app, and one app can have several of these processes, which
        // then collapse into a single row.
        let responsible = responsibility_get_pid_responsible_for_pid(pid)
        if responsible > 0, responsible != pid, let app = regularApp(responsible) { return app }

        // Chromium and Electron helpers are the other way around: each one is
        // responsible for itself, and the parent chain is what leads back to
        // the browser.
        var current = pid
        for _ in 0 ..< ownerSearchDepth {
            current = parentPID(of: current)
            guard current > 1 else { return nil }
            if let app = regularApp(current) { return app }
        }
        return nil
    }

    private static func regularApp(_ pid: pid_t) -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular else { return nil }
        return app
    }

    private static func parentPID(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&name, UInt32(name.count), &info, &size, nil, 0) == 0, size > 0 else { return -1 }
        return info.kp_eproc.e_ppid
    }

    private static func isBypassed(bundleIdentifier: String?, name: String) -> Bool {
        let bundle = (bundleIdentifier ?? "").lowercased()
        if bypassedBundlePrefixes.contains(where: bundle.hasPrefix) { return true }
        return name.lowercased().hasPrefix("zoom")
    }

    // MARK: - CoreAudio reads

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func bundleIdentifier(of object: AudioObjectID) -> String? {
        var value: CFString?
        guard read(object, kAudioProcessPropertyBundleID, into: &value) else { return nil }
        let identifier = value as String?
        return (identifier?.isEmpty ?? true) ? nil : identifier
    }

    static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, UnsafeMutableRawPointer($0)) == noErr
        }
    }
}

/// The output device everything is rendered to, and the system volume beside
/// it so the panel can show one place for both.
enum AudioOutputDevice {
    static var defaultDeviceID: AudioObjectID? {
        var device = AudioObjectID(0)
        guard AudioProcessCatalog.read(
            AudioObjectID(kAudioObjectSystemObject),
            kAudioHardwarePropertyDefaultOutputDevice,
            into: &device
        ), device != 0 else { return nil }
        return device
    }

    static var defaultDeviceUID: String? {
        guard let device = defaultDeviceID else { return nil }
        var uid: CFString?
        guard AudioProcessCatalog.read(device, kAudioDevicePropertyDeviceUID, into: &uid) else { return nil }
        return uid as String?
    }

    static var defaultDeviceName: String? {
        guard let device = defaultDeviceID else { return nil }
        var name: CFString?
        guard AudioProcessCatalog.read(device, kAudioObjectPropertyName, into: &name) else { return nil }
        return name as String?
    }
}
