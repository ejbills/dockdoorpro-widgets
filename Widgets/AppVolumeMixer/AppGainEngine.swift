import Accelerate
import AudioToolbox
import CoreAudio
import Foundation

/// Applies a tapped app's samples to the output device, scaled by a gain that
/// the main thread can change at any time.
///
/// Everything here runs on the realtime audio thread: no allocation, no locks,
/// one pass over the samples.
enum MixerRender {
    /// Loudest an app can be driven: twice its own output.
    static let maximumGain: Float = 2

    /// Loudest sample the limiter lets out, a shade under full scale so the
    /// device never receives a sample sitting on the edge.
    static let ceiling: Float = 0.95

    static func frames(bytes: UInt32, channels: UInt32) -> Int {
        guard channels > 0 else { return 0 }
        return Int(bytes) / (MemoryLayout<Float>.size * Int(channels))
    }

    /// Which input buffer carries the tap.
    ///
    /// An aggregate presents its sub-device's own input first and the tap
    /// after it, so on an output device that also records, the tap is not
    /// buffer zero — rendering that one plays the microphone's silence and the
    /// app goes quiet. Match the shape the tap announced; with nothing
    /// matching and only one buffer present, it has nowhere else to come from.
    static func tapBufferIndex(in buffers: UnsafeMutableAudioBufferListPointer, tapChannels: Int) -> Int? {
        var lone: Int?
        for index in stride(from: buffers.count - 1, through: 0, by: -1)
            where buffers[index].mData != nil && buffers[index].mNumberChannels > 0
        {
            if Int(buffers[index].mNumberChannels) == tapChannels { return index }
            if buffers.count == 1 { lone = index }
        }
        return lone
    }

    /// Silences every output frame from `frame` on.
    ///
    /// Output buffers arrive holding whatever CoreAudio last left in that
    /// memory. A frame with no samples behind it has to be written silent or
    /// the device plays back a fragment of older audio.
    static func silence(_ output: UnsafeMutableAudioBufferListPointer, from frame: Int = 0) {
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0, let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let unwritten = frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels) - frame
            guard unwritten > 0 else { continue }
            vDSP_vclr(destination + frame * channels, 1, vDSP_Length(unwritten * channels))
        }
    }

    /// Which source channel feeds one output channel, or nil when the device
    /// has more channels than the tap can fill.
    static func sourceChannel(for outputChannel: Int, sourceChannels: Int) -> Int? {
        if outputChannel < sourceChannels { return outputChannel }
        // A mono source belongs in both front channels, not just the left one.
        if sourceChannels == 1, outputChannel == 1 { return 0 }
        return nil
    }

    /// Fills `frameGains` with the per-frame gain to apply.
    ///
    /// Two things happen per frame. The gain slides toward whatever the slider
    /// last asked for instead of jumping there, because a step change part way
    /// through a waveform is a click, and a drag is a stream of step changes.
    ///
    /// Then, above unity only, the limiter: a boost pushes loud material past
    /// full scale, and clamping sample by sample flattens every peak into
    /// crackle. Turning the whole signal down for exactly as long as a peak
    /// would not fit reads as loudness rather than distortion. The envelope
    /// drops instantly and recovers exponentially, and all channels of a frame
    /// share one gain so the stereo image stays put.
    static func fillFrameGains(
        _ frameGains: UnsafeMutablePointer<Float>,
        frames: Int,
        source: UnsafePointer<Float>,
        sourceChannels: Int,
        target: Float,
        current: UnsafeMutablePointer<Float>,
        smoothing: Float,
        envelope: UnsafeMutablePointer<Float>,
        release: Float
    ) {
        var gain = current.pointee

        // Settled below unity: nothing to ramp and nothing that can clip.
        if target <= 1, abs(gain - target) < 0.0001 {
            var flat = target
            vDSP_vfill(&flat, frameGains, 1, vDSP_Length(frames))
            current.pointee = target
            envelope.pointee = 1
            return
        }

        var level = envelope.pointee
        for frame in 0 ..< frames {
            gain = target + (gain - target) * smoothing
            guard gain > 1 else {
                level = 1
                frameGains[frame] = gain
                continue
            }
            var peak: Float = 0
            let base = frame * sourceChannels
            for channel in 0 ..< sourceChannels {
                peak = max(peak, abs(source[base + channel]))
            }
            let boosted = peak * gain
            let ceilingGain: Float = boosted > ceiling ? ceiling / boosted : 1
            level = ceilingGain < level ? ceilingGain : ceilingGain + (level - ceilingGain) * release
            frameGains[frame] = level * gain
        }
        current.pointee = gain
        envelope.pointee = level
    }

    /// Renders one interleaved source buffer onto the output using a per-frame
    /// gain vector, and answers how many frames it wrote. Whatever it does not
    /// write it silences, so the caller never has to think about the tail.
    @discardableResult
    static func render(
        source: AudioBuffer,
        into output: UnsafeMutableAudioBufferListPointer,
        frameGains: UnsafePointer<Float>,
        frames: Int
    ) -> Int {
        var written = 0
        defer { silence(output, from: written) }

        let sourceChannels = Int(source.mNumberChannels)
        guard frames > 0, sourceChannels > 0,
              let samples = source.mData?.assumingMemoryBound(to: Float.self) else { return 0 }

        var outputChannels = 0
        for buffer in output where buffer.mNumberChannels > 0 && buffer.mData != nil {
            outputChannels += Int(buffer.mNumberChannels)
        }
        guard outputChannels > 0 else { return 0 }

        // One channel to play with: fold the source into it instead of handing
        // over every other sample, which would play at the wrong speed.
        if outputChannels == 1, sourceChannels > 1 {
            guard let buffer = output.first(where: { $0.mNumberChannels == 1 && $0.mData != nil }),
                  let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
            let stride = vDSP_Stride(sourceChannels)
            vDSP_vmul(samples, stride, frameGains, 1, destination, 1, vDSP_Length(frames))
            for channel in 1 ..< sourceChannels {
                vDSP_vma(samples + channel, stride, frameGains, 1, destination, 1, destination, 1, vDSP_Length(frames))
            }
            var scale = 1 / Float(sourceChannels)
            vDSP_vsmul(destination, 1, &scale, destination, 1, vDSP_Length(frames))
            written = frames
            return written
        }

        var firstOutputChannel = 0
        var wroteAnything = false
        for buffer in output {
            let channels = Int(buffer.mNumberChannels)
            guard channels > 0 else { continue }
            defer { firstOutputChannel += channels }
            guard let destination = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for channel in 0 ..< channels {
                guard let sourceChannel = sourceChannel(
                    for: firstOutputChannel + channel,
                    sourceChannels: sourceChannels
                ) else {
                    vDSP_vclr(destination + channel, vDSP_Stride(channels), vDSP_Length(frames))
                    continue
                }
                wroteAnything = true
                vDSP_vmul(
                    samples + sourceChannel, vDSP_Stride(sourceChannels),
                    frameGains, 1,
                    destination + channel, vDSP_Stride(channels),
                    vDSP_Length(frames)
                )
            }
        }
        written = wroteAnything ? frames : 0
        return written
    }
}

/// The audio path for one adjusted app: a muted process tap feeding a private
/// aggregate device whose IO proc re-renders the tapped samples onto the
/// output at the requested gain.
///
/// macOS has no per-app volume of its own. `.mutedWhenTapped` takes the app's
/// sound off the real output, which leaves this engine holding the only copy
/// of it — so an engine that dies without being replaced hands the app
/// straight back to the speakers at full volume, and one that stops rendering
/// leaves it silent. Both failure modes are handled by the model above.
@available(macOS 14.4, *)
final class AppGainEngine {
    let audioObjects: [AudioObjectID]
    let outputDeviceUID: String

    /// Shared with the audio thread. All four are plain heap words touched
    /// without locks: `gain` is written by the main thread and read by the
    /// audio thread, `renderCycles` the other way around, and an aligned
    /// 32/64-bit word is written whole on every architecture the app runs on.
    /// The scratch buffers below belong to the audio thread alone.
    private let gainPointer: UnsafeMutablePointer<Float>
    private let cyclesPointer: UnsafeMutablePointer<UInt64>
    private let envelopePointer: UnsafeMutablePointer<Float>
    /// The gain actually being rendered, which slides toward `gainPointer`.
    private let smoothedGainPointer: UnsafeMutablePointer<Float>
    private let frameGains: UnsafeMutablePointer<Float>
    private let frameGainCapacity: Int

    private var tapID = AudioObjectID(0)
    private var aggregateID = AudioObjectID(0)
    private var ioProcID: AudioDeviceIOProcID?
    private var stopped = false

    /// How many IO cycles the engine has completed. A count that stops moving
    /// while the app is playing means the aggregate is no longer rendering and
    /// the tap can now only mute the app.
    var renderCycles: UInt64 { cyclesPointer.pointee }

    var gain: Float {
        get { gainPointer.pointee }
        set { gainPointer.pointee = min(max(newValue, 0), MixerRender.maximumGain) }
    }

    init?(audioObjects: [AudioObjectID], gain: Float, outputDeviceUID: String) {
        guard !audioObjects.isEmpty else { return nil }
        self.audioObjects = audioObjects
        self.outputDeviceUID = outputDeviceUID

        let description = CATapDescription(stereoMixdownOfProcesses: audioObjects)
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr, tapID != 0 else {
            return nil
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "DockDoor Volume Mixer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputDeviceUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID) == noErr,
              aggregateID != 0
        else {
            AudioHardwareDestroyProcessTap(tapID)
            return nil
        }

        gainPointer = .allocate(capacity: 1)
        gainPointer.initialize(to: min(max(gain, 0), MixerRender.maximumGain))
        cyclesPointer = .allocate(capacity: 1)
        cyclesPointer.initialize(to: 0)
        envelopePointer = .allocate(capacity: 1)
        envelopePointer.initialize(to: 1)
        smoothedGainPointer = .allocate(capacity: 1)
        // Starts where it is asked to start: the first engine for an app
        // should not ramp up from silence.
        smoothedGainPointer.initialize(to: gainPointer.pointee)
        // Sized well past any IO buffer the HAL asks for, so a device that
        // switches to a larger buffer mid-stream is still covered.
        frameGainCapacity = max(16384, Self.bufferFrameSize(of: aggregateID) * 4)
        frameGains = .allocate(capacity: frameGainCapacity)
        frameGains.initialize(repeating: 1, count: frameGainCapacity)

        // Only trivial values are captured, so the audio thread never touches
        // a Swift reference count.
        let gainWord = gainPointer
        let cycleWord = cyclesPointer
        let envelopeWord = envelopePointer
        let smoothedWord = smoothedGainPointer
        let gains = frameGains
        let capacity = frameGainCapacity
        let tapChannels = Self.tapChannels(of: tapID)
        let rate = Self.sampleRate(of: aggregateID)
        let release = Self.coefficient(seconds: 0.15, sampleRate: rate)
        let smoothing = Self.coefficient(seconds: 0.012, sampleRate: rate)

        let created = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, nil) { _, input, _, output, _ in
            let inputBuffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputBuffers = UnsafeMutableAudioBufferListPointer(output)
            guard let tapIndex = MixerRender.tapBufferIndex(in: inputBuffers, tapChannels: tapChannels) else {
                MixerRender.silence(outputBuffers)
                return
            }

            let source = inputBuffers[tapIndex]
            let sourceChannels = Int(source.mNumberChannels)
            var frames = MixerRender.frames(bytes: source.mDataByteSize, channels: source.mNumberChannels)
            for buffer in outputBuffers where buffer.mNumberChannels > 0 && buffer.mData != nil {
                frames = min(frames, MixerRender.frames(bytes: buffer.mDataByteSize, channels: buffer.mNumberChannels))
            }
            frames = min(frames, capacity)
            guard frames > 0, sourceChannels > 0,
                  let samples = source.mData?.assumingMemoryBound(to: Float.self)
            else {
                MixerRender.silence(outputBuffers)
                return
            }

            MixerRender.fillFrameGains(
                gains,
                frames: frames,
                source: samples,
                sourceChannels: sourceChannels,
                target: gainWord.pointee,
                current: smoothedWord,
                smoothing: smoothing,
                envelope: envelopeWord,
                release: release
            )
            let written = MixerRender.render(source: source, into: outputBuffers, frameGains: gains, frames: frames)
            if written > 0 { cycleWord.pointee &+= 1 }
        }
        guard created == noErr else {
            teardown()
            return nil
        }
        guard AudioDeviceStart(aggregateID, ioProcID) == noErr else {
            teardown()
            return nil
        }
    }

    deinit {
        stop()
    }

    /// Idempotent. Safe to call from the main thread: the CoreAudio teardown
    /// runs off it because destroying a wedged tap can block for a long time.
    func stop() {
        guard !stopped else { return }
        stopped = true
        teardown()
    }

    private func teardown() {
        let tap = tapID
        let aggregate = aggregateID
        let proc = ioProcID
        let gainWord = gainPointer
        let cycleWord = cyclesPointer
        let envelopeWord = envelopePointer
        let smoothedWord = smoothedGainPointer
        let gains = frameGains
        tapID = 0
        aggregateID = 0
        ioProcID = nil

        Self.teardownQueue.async {
            if let proc, aggregate != 0 {
                AudioDeviceStop(aggregate, proc)
                AudioDeviceDestroyIOProcID(aggregate, proc)
            }
            if aggregate != 0 { AudioHardwareDestroyAggregateDevice(aggregate) }
            if tap != 0 { AudioHardwareDestroyProcessTap(tap) }
            // Only once the IO proc can no longer be called.
            gainWord.deallocate()
            cycleWord.deallocate()
            envelopeWord.deallocate()
            smoothedWord.deallocate()
            gains.deallocate()
        }
    }

    /// Bounded so a HAL call that parks inside teardown cannot take the whole
    /// thread pool with it.
    private static let teardownQueue = DispatchQueue(
        label: "net.dockdoor.widget.volume-mixer.teardown",
        qos: .utility
    )

    private static func tapChannels(of tap: AudioObjectID) -> Int {
        var format = AudioStreamBasicDescription()
        guard AudioProcessCatalog.read(tap, kAudioTapPropertyFormat, into: &format),
              format.mChannelsPerFrame > 0 else { return 2 }
        return Int(format.mChannelsPerFrame)
    }

    private static func sampleRate(of device: AudioObjectID) -> Double {
        var rate: Float64 = 0
        guard AudioProcessCatalog.read(device, kAudioDevicePropertyNominalSampleRate, into: &rate),
              rate > 0 else { return 48000 }
        return rate
    }

    private static func bufferFrameSize(of device: AudioObjectID) -> Int {
        var frames: UInt32 = 0
        guard AudioProcessCatalog.read(device, kAudioDevicePropertyBufferFrameSize, into: &frames),
              frames > 0 else { return 512 }
        return Int(frames)
    }

    /// How much of the previous value survives one sample, so a slide takes
    /// the same fraction of a second whatever the device's rate.
    private static func coefficient(seconds: Double, sampleRate: Double) -> Float {
        Float(exp(-1.0 / (sampleRate * seconds)))
    }
}
