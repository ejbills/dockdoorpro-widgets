import AppKit
import CoreAudio
import DockDoorWidgetSDK
import Foundation
import SwiftUI

/// Holds a notification token so it is unregistered when the model goes away,
/// without a main-actor deinit having to reach for it.
private final class NotificationObserverBox: @unchecked Sendable {
    var token: NSObjectProtocol?

    deinit {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}

/// Per-app volume, which macOS itself does not offer.
///
/// Every app that is turned down (or boosted) gets a muted CoreAudio process
/// tap that takes its sound off the output device, plus a private aggregate
/// device that renders the tapped samples back at the chosen gain. Apps left
/// at 100% are never tapped at all, so the untouched case is untouched: the
/// mixer cannot mute or colour an app the user never adjusted.
///
/// Requires macOS 14.4 (process taps) and the host app's System Audio
/// Recording permission. Without consent, tap creation fails and every app
/// keeps playing normally — the panel says so instead of going quiet.
@MainActor
@Observable
final class AppVolumeMixerModel {
    /// Volumes run 0...2, where 1 is untouched passthrough and 2 doubles a
    /// source that plays too quietly.
    static var maximumVolumeValue: Float { MixerRender.maximumGain }

    private(set) var entries: [MixerEntry] = []
    private(set) var outputDeviceName: String?
    /// Set when a tap is refused, which in practice means the host app has no
    /// System Audio Recording consent yet.
    private(set) var needsPermission = false
    var isSupported: Bool { if #available(macOS 14.4, *) { true } else { false } }

    private let widgetId: String
    private var volumes: [String: Double] = [:]
    private var lastAudibleVolume: [String: Double] = [:]
    private var engines: [String: AnyObject] = [:]
    private var buildTokens: [String: Int] = [:]
    private var buildsInFlight: [String: String] = [:]
    private var renderProgress: [String: UInt64] = [:]
    private var failedConfigurations: Set<String> = []
    private var outputDeviceUID: String?
    private var lastRefresh = Date.distantPast
    private let terminationObserver = NotificationObserverBox()
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let buildQueue = DispatchQueue(label: "net.dockdoor.widget.volume-mixer.build", qos: .userInitiated)

    init(widgetId: String) {
        self.widgetId = widgetId
        volumes = Self.loadVolumes(widgetId: widgetId)
        // Taps outlive the widget's views, so the app going away is the one
        // moment every app has to be handed back to the speakers.
        terminationObserver.token = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.releaseAllEngines() }
        }
    }

    // MARK: - Lifecycle

    /// Called from the views' `TimelineView` ticks, so polling stops on its
    /// own when neither the dock icon nor the panel is on screen. The interval
    /// guard keeps the two of them from sampling twice per tick when both are.
    func tick(minimumInterval: TimeInterval) {
        guard Date().timeIntervalSince(lastRefresh) >= minimumInterval else { return }
        refresh()
    }

    func refresh() {
        guard isSupported else { return }
        lastRefresh = Date()
        entries = AudioProcessCatalog.entries(excluding: ownPID)
        outputDeviceUID = AudioOutputDevice.defaultDeviceUID
        outputDeviceName = AudioOutputDevice.defaultDeviceName
        reconcileEngines()
    }

    // MARK: - Reading and writing volumes

    func volume(for entry: MixerEntry) -> Double {
        guard !entry.isBypassed else { return 1 }
        // Clamped on the way out, so turning the boost setting back off also
        // brings down an app that was left above 100%.
        return min(volumes[entry.key] ?? 1, maximumVolume())
    }

    func isAdjusted(_ entry: MixerEntry) -> Bool {
        !Self.isUnity(volume(for: entry))
    }

    func setVolume(_ value: Double, for entry: MixerEntry) {
        guard !entry.isBypassed else { return }
        let clamped = min(max(value, 0), maximumVolume())
        if Self.isUnity(clamped) {
            volumes.removeValue(forKey: entry.key)
        } else {
            volumes[entry.key] = clamped
        }
        // A fresh ask is a fresh attempt: a path that gave up once gets to try
        // again rather than leaving the row stuck untapped for good.
        failedConfigurations.removeAll()
        persistVolumes()
        applyRouting(for: entry)
    }

    func toggleMute(_ entry: MixerEntry) {
        let current = volume(for: entry)
        if current > 0.001 {
            lastAudibleVolume[entry.key] = current
            setVolume(0, for: entry)
        } else {
            setVolume(lastAudibleVolume[entry.key] ?? 1, for: entry)
        }
    }

    func resetAll() {
        volumes.removeAll()
        persistVolumes()
        releaseAllEngines()
    }

    /// The row the dock icon reflects and the scroll wheel drives: the
    /// frontmost app when it has audio, otherwise whatever is playing.
    var primaryEntry: MixerEntry? {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if let frontmostPID, let match = entries.first(where: { $0.pid == frontmostPID }), !match.isBypassed {
            return match
        }
        return entries.first { $0.isPlaying && !$0.isBypassed }
            ?? entries.first { !$0.isBypassed }
    }

    var adjustedEntries: [MixerEntry] {
        entries.filter { isAdjusted($0) }
    }

    // MARK: - Engines

    private func maximumVolume() -> Double {
        WidgetDefaults.bool(key: "allowBoost", widgetId: widgetId, default: false)
            ? Double(Self.maximumVolumeValue)
            : 1
    }

    var boostEnabled: Bool { maximumVolume() > 1 }

    private static func isUnity(_ volume: Double) -> Bool {
        abs(volume - 1) < 0.005
    }

    private func configurationKey(_ objects: [AudioObjectID], _ outputUID: String) -> String {
        "\(objects.map(String.init).joined(separator: ","))@\(outputUID)"
    }

    /// Brings one row's audio path in line with its volume. Replacements are
    /// built before the old engine stops: a tap that goes away for even a
    /// moment hands the app back to the speakers at full volume.
    private func applyRouting(for entry: MixerEntry) {
        guard #available(macOS 14.4, *), isSupported else { return }
        let gain = volume(for: entry)

        guard !entry.isBypassed, !Self.isUnity(gain), !entry.audioObjects.isEmpty,
              let outputUID = outputDeviceUID
        else {
            discardEngine(for: entry.key)
            return
        }

        if let engine = engines[entry.key] as? AppGainEngine {
            if engine.audioObjects == entry.audioObjects, engine.outputDeviceUID == outputUID {
                engine.gain = Float(gain)
                return
            }
        }

        let configuration = configurationKey(entry.audioObjects, outputUID)
        // One replacement per broken path. If the same build fails to render
        // twice, the row stays untapped so the app keeps playing.
        guard !failedConfigurations.contains(configuration) else { return }
        // While a slider keeps moving, one build is enough. Every extra build
        // is a real tap that mutes the app for as long as it lives, which is
        // what made a drag cut in and out, and `install` below applies
        // whatever volume the drag ended on anyway.
        guard buildsInFlight[entry.key] != configuration else { return }

        let token = (buildTokens[entry.key] ?? 0) + 1
        buildTokens[entry.key] = token
        buildsInFlight[entry.key] = configuration
        let objects = entry.audioObjects
        let key = entry.key

        buildQueue.async { [weak self] in
            let engine = AppGainEngine(audioObjects: objects, gain: Float(gain), outputDeviceUID: outputUID)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else {
                        engine?.stop()
                        return
                    }
                    self.install(engine, for: key, token: token)
                }
            }
        }
    }

    private func install(_ engine: AnyObject?, for key: String, token: Int) {
        guard #available(macOS 14.4, *) else { return }
        // A build that started before the mixer moved on would leave a second
        // live tap on the app and render its sound twice.
        guard buildTokens[key] == token else {
            // A newer build is still in flight; its own install clears the slot.
            (engine as? AppGainEngine)?.stop()
            return
        }

        buildsInFlight.removeValue(forKey: key)

        guard let engine = engine as? AppGainEngine else {
            // Nothing was created, so nothing is muted: the app plays as it
            // always did. The only common cause is missing consent.
            needsPermission = engines[key] == nil
            return
        }

        guard let entry = entries.first(where: { $0.key == key }),
              !Self.isUnity(volume(for: entry)),
              entry.audioObjects == engine.audioObjects,
              engine.outputDeviceUID == outputDeviceUID
        else {
            // The slider moved back to 100%, or the app's audio changed shape,
            // while the engine was being built.
            engine.stop()
            if let entry = entries.first(where: { $0.key == key }) { applyRouting(for: entry) }
            return
        }

        needsPermission = false
        engine.gain = Float(volume(for: entry))
        let previous = engines[key] as? AppGainEngine
        engines[key] = engine
        renderProgress.removeValue(forKey: key)
        previous?.stop()
    }

    private func discardEngine(for key: String) {
        guard #available(macOS 14.4, *) else { return }
        (engines.removeValue(forKey: key) as? AppGainEngine)?.stop()
        renderProgress.removeValue(forKey: key)
        buildsInFlight.removeValue(forKey: key)
        buildTokens[key] = (buildTokens[key] ?? 0) + 1
    }

    private func releaseAllEngines() {
        guard #available(macOS 14.4, *) else { return }
        for key in engines.keys { buildTokens[key] = (buildTokens[key] ?? 0) + 1 }
        buildsInFlight.removeAll()
        for engine in engines.values { (engine as? AppGainEngine)?.stop() }
        engines.removeAll()
        renderProgress.removeAll()
    }

    /// Runs on every refresh: rebuilds rows whose audio objects or output
    /// device changed, drops engines whose app is gone, and catches an
    /// aggregate the HAL quietly stopped driving.
    private func reconcileEngines() {
        guard #available(macOS 14.4, *) else { return }
        let byKey = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0) })

        for (key, boxed) in engines {
            guard let engine = boxed as? AppGainEngine else { continue }
            guard let entry = byKey[key] else {
                // The app quit; its tap went with it.
                discardEngine(for: key)
                continue
            }

            // A muted tap that stopped rendering leaves the app silent, so a
            // stalled engine goes immediately — that alone unmutes the app —
            // and gets one replacement.
            if entry.isPlaying {
                let cycles = engine.renderCycles
                if let previous = renderProgress[key], previous == cycles {
                    failedConfigurations.insert(configurationKey(engine.audioObjects, engine.outputDeviceUID))
                    discardEngine(for: key)
                    applyRouting(for: entry)
                    continue
                }
                renderProgress[key] = cycles
            }
        }

        for entry in entries {
            applyRouting(for: entry)
        }
    }

    // MARK: - Persistence

    private static func storageKey(_ widgetId: String) -> String { "\(widgetId).appVolumes" }

    private static func loadVolumes(widgetId: String) -> [String: Double] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(widgetId)),
              let saved = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return [:] }
        return saved
    }

    private func persistVolumes() {
        guard let data = try? JSONEncoder().encode(volumes) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey(widgetId))
    }
}
