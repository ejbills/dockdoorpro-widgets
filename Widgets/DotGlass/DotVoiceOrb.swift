import AppKit
import MetalKit
import SwiftUI

/// Independent renderer. Audio is normalized 0...1; no voice-service dependency.
enum VoiceOrbState: Float { case idle = 0, listening = 1, speaking = 2 }
struct VoiceOrbConfiguration {
    var colors: [Color] = DotTheme.orchid.colors
    var glowStrength: Float = 0.22
    var motionSpeed: Float = 1
    var deformationStrength: Float = 0.008
    var sensitivity: Float = 1.5
    var attack: Float = 0.08
    var release: Float = 0.38
}

struct DotVoiceOrb: NSViewRepresentable {
    var state: VoiceOrbState = .idle
    var audioLevel: Double = 0
    var configuration = VoiceOrbConfiguration()
    @Environment(\.accessibilityReduceMotion) private var reduced

    func makeCoordinator() -> VoiceOrbRenderer { VoiceOrbRenderer() }
    func makeNSView(context: Context) -> VoiceOrbMetalView {
        let view = VoiceOrbMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.layer?.isOpaque = false
        view.delegate = context.coordinator
        context.coordinator.prepare(view)
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: VoiceOrbMetalView, context: Context) {
        context.coordinator.state = state
        context.coordinator.level = Float(audioLevel.isFinite ? max(0, min(1, audioLevel)) : 0)
        context.coordinator.configuration = configuration
        context.coordinator.reduced = reduced
        view.shouldAnimate = !reduced && state != .idle
        view.isPaused = !view.shouldAnimate || view.window == nil
        if view.isPaused { view.draw() }
    }
    static func dismantleNSView(_ view: VoiceOrbMetalView, coordinator: VoiceOrbRenderer) {
        view.isPaused = true; view.delegate = nil
    }
}

final class VoiceOrbMetalView: MTKView {
    var shouldAnimate = false
    override var isOpaque: Bool { false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isPaused = !shouldAnimate || window == nil
        if isPaused && window != nil { draw() }
    }
}

final class VoiceOrbRenderer: NSObject, MTKViewDelegate {
    var state = VoiceOrbState.idle
    var level: Float = 0
    var configuration = VoiceOrbConfiguration()
    var reduced = false
    private var queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var origin = CACurrentMediaTime()
    private var previous = CACurrentMediaTime()
    private var smoothed: Float = 0
    private var activity: Float = 0

    func prepare(_ view: MTKView) {
        guard let device = view.device else { return }
        queue = device.makeCommandQueue()
        do {
            let library = try device.makeLibrary(source: Self.shader, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "orbVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "orbFragment")
            let color = descriptor.colorAttachments[0]!
            color.pixelFormat = view.colorPixelFormat
            color.isBlendingEnabled = true
            color.sourceRGBBlendFactor = .one
            color.destinationRGBBlendFactor = .oneMinusSourceAlpha
            color.sourceAlphaBlendFactor = .one
            color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            // No page, account or message data enters the renderer.
            NSLog("Dot Glass: voice-orb GPU pipeline unavailable")
        }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let pipeline, let queue, let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let command = queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        let now = CACurrentMediaTime()
        let delta = Float(min(0.1, max(0.001, now - previous))); previous = now
        let target = min(1, max(0, level * max(0, configuration.sensitivity)))
        let duration = target > smoothed ? configuration.attack : configuration.release
        smoothed += (target - smoothed) * (1 - exp(-delta / max(0.01, duration)))
        activity += (state.rawValue - activity) * (1 - exp(-delta / 0.28))
        let colors = configuration.colors.isEmpty ? DotTheme.orchid.colors : configuration.colors
        func rgba(_ color: Color) -> SIMD4<Float> {
            let rgb = NSColor(color).usingColorSpace(.deviceRGB) ?? .systemPurple
            return SIMD4(Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent), 1)
        }
        var uniforms = [
            SIMD4<Float>(reduced ? 0 : Float(now - origin), Float(min(view.drawableSize.width, view.drawableSize.height)), reduced ? 0 : smoothed, reduced ? 0 : activity),
            SIMD4<Float>(max(0, configuration.glowStrength), max(0, configuration.motionSpeed), reduced ? 0 : max(0, configuration.deformationStrength), reduced ? 1 : 0),
            rgba(colors[0]), rgba(colors[min(1, colors.count - 1)]), rgba(colors[min(2, colors.count - 1)])
        ]
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SIMD4<Float>>.stride * uniforms.count, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding(); command.present(drawable); command.commit()
    }

    // Embedded shader keeps the marketplace bundle source-only and self-contained.
    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;
    struct Vertex { float4 position [[position]]; float2 uv; };
    struct Uniforms { float4 dynamics; float4 behavior; float4 color0; float4 color1; float4 color2; };
    vertex Vertex orbVertex(uint id [[vertex_id]]) {
        float2 p = id == 0 ? float2(-1,-1) : id == 1 ? float2(3,-1) : float2(-1,3);
        return {float4(p,0,1), float2((p.x+1)*0.5, (1-p.y)*0.5)};
    }
    float hash(float2 p) { return fract(sin(dot(p,float2(127.1,311.7))) * 43758.5453); }
    float noise(float2 p) {
        float2 i = floor(p), f = fract(p); f = f*f*(3-2*f);
        return mix(mix(hash(i),hash(i+float2(1,0)),f.x),mix(hash(i+float2(0,1)),hash(i+1),f.x),f.y);
    }
    float fbm(float2 p) {
        float sum=0, weight=0.5;
        for(int i=0;i<5;i++) { sum += weight*noise(p); p=float2(p.x*1.7-p.y*1.1,p.x*1.1+p.y*1.7)+3.7; weight*=0.5; }
        return sum;
    }
    fragment float4 orbFragment(Vertex in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float t=u.dynamics.x*u.behavior.y, audio=u.dynamics.z;
        float speaking=smoothstep(1.0,2.0,u.dynamics.w);
        float breathing=u.behavior.w > 0.5 ? 0 : sin(t*3.65)*0.027;
        float2 p=in.uv-float2(0.5);
        float angle=atan2(p.y,p.x);
        float deformation=u.behavior.z*speaking*audio*(sin(angle*3+t*0.8)*0.55+sin(angle*5-t)*0.25);
        float radius=0.425+breathing+audio*speaking*0.015+deformation;
        float d=length(p), pixel=1.3/max(1.0,u.dynamics.y);
        float edge=1-smoothstep(radius-pixel,radius+pixel,d);
        float n=fbm(p*5.8+float2(t*0.075,-t*0.11));
        float warp=fbm(p*9+float2(-t*0.09,t*0.045)+n*1.9);
        float tilt=sin(t*0.22)*0.32;
        float band=p.y+tilt*p.x+(n-0.5)*0.14+sin(t*0.48)*0.08;
        float cloudy=exp(-pow((band+(warp-0.5)*0.09)/0.11,2.0));
        float wisps=fbm(p*23+float2(t*0.11,-t*0.06)+warp*3);
        float3 purple=mix(u.color0.rgb,u.color1.rgb,0.15);
        float3 pale=mix(u.color0.rgb,float3(1),0.64);
        float3 base=mix(purple,pale,smoothstep(-0.15,0.25,p.y+(n-0.5)*0.1));
        float light=clamp(cloudy*(0.67+wisps*0.35)+(warp-0.45)*0.1,0.0,0.95);
        float3 cloud=mix(float3(1),u.color2.rgb,0.12);
        float3 color=mix(base,cloud,light);
        float halo=exp(-pow(max(0.0,d-radius)/0.036,2.0))*u.behavior.x*0.16*(1-edge);
        float alpha=clamp(edge+halo,0.0,1.0);
        color=mix(u.color0.rgb,color,edge);
        return float4(color*alpha,alpha);
    }
    """
}
