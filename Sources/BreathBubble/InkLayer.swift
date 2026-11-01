import AppKit
import MetalKit

/// How the screen fills with black when focus starts.
enum FocusStyle: String, CaseIterable {
    case fade, tide, ink

    var name: String {
        switch self {
        case .fade: return "Fade"
        case .tide: return "Tide"
        case .ink: return "Ink"
        }
    }

    static func named(_ id: String?) -> FocusStyle { FocusStyle(rawValue: id ?? "") ?? .tide }
}

/// What the shader needs each frame. The layout matches `Uniforms` in the shader source below.
struct InkUniforms {
    var bubble = SIMD2<Float>(0.5, 0.5)  // the bubble's centre now, 0...1 across the screen (origin bottom left)
    var origin = SIMD2<Float>(0.5, 0.5)  // where the bubble was when focus started; the ink spills from here
    var aspect: Float = 1.6              // width / height
    var time: Float = 0                  // seconds since focus started, for the slow drift of the edge
    var progress: Float = 0              // 0 is the desktop as it was, 1 is all black
    var fade: Float = 1                  // multiplies the darkness; leaving fades it out evenly
    var maxFromBubble: Float = 1         // distance from the bubble to the farthest corner, in screen heights
    var maxFromOrigin: Float = 1         // the same from the origin
    var mode: Int32 = 1                  // 1 tide, 2 ink
    var pad: Int32 = 0
}

/// Draws the black fill for the Tide and Ink styles with a small Metal shader.
/// It draws only when asked (`render`), so it costs nothing while focus holds.
final class InkLayer: MTKView {
    private static let device = MTLCreateSystemDefaultDevice()
    private static var pipeline: MTLRenderPipelineState?
    private var queue: MTLCommandQueue?
    var uniforms = InkUniforms()

    /// Returns nil when Metal isn't available; focus then falls back to the plain fade.
    init?(size: NSSize) {
        let frame = NSRect(origin: .zero, size: size)
        guard let device = InkLayer.device, let pipeline = InkLayer.makePipeline(device) else { return nil }
        InkLayer.pipeline = pipeline
        super.init(frame: frame, device: device)
        queue = device.makeCommandQueue()
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        layer?.isOpaque = false
        isPaused = true
        enableSetNeedsDisplay = false
        // The edge is soft, so drawing at one pixel per point is plenty, even on a 6K screen.
        autoResizeDrawable = false
        drawableSize = frame.size
        autoresizingMask = [.width, .height]
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }  // clicks go to the focus view behind

    func render() {
        // Ask the layer for a fresh drawable each time; MTKView's own one is meant for its draw loop.
        guard let pipeline = InkLayer.pipeline, let queue, let metal = layer as? CAMetalLayer,
              let drawable = metal.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = clearColor
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        var u = uniforms
        encoder.setFragmentBytes(&u, length: MemoryLayout<InkUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Draws one frame offscreen and returns it, for checking the look without covering the screen.
    static func snapshot(_ uniforms: InkUniforms, width: Int, height: Int) -> CGImage? {
        guard let device, let pipeline = makePipeline(device), let queue = device.makeCommandQueue() else { return nil }
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]
        td.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: td), let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.setRenderPipelineState(pipeline)
        var u = uniforms
        encoder.setFragmentBytes(&u, length: MemoryLayout<InkUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func makePipeline(_ device: MTLDevice) -> MTLRenderPipelineState? {
        if let pipeline { return pipeline }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = library.makeFunction(name: "inkVertex")
            d.fragmentFunction = library.makeFunction(name: "inkFragment")
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            return try device.makeRenderPipelineState(descriptor: d)
        } catch {
            NSLog("Focus shader failed: \(error)")
            return nil
        }
    }

    /// Tide: a wide, soft edge of dark closes in from every side and settles on the bubble.
    /// Ink: ink spills out of the bubble with a slowly drifting edge.
    /// Both reach full black at progress 1 by themselves. The colour is premultiplied: black with alpha `dark`.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float2 bubble; float2 origin; float aspect; float time; float progress; float fade;
        float maxFromBubble; float maxFromOrigin; int mode; int pad;
    };
    struct VOut { float4 position [[position]]; float2 uv; };

    vertex VOut inkVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        VOut o;
        o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = p;
        return o;
    }

    static float hash(float2 p) { p = fract(p * float2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
    static float noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
        return mix(mix(hash(i), hash(i + float2(1, 0)), f.x), mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), f.x), f.y);
    }
    static float fbm3(float2 p) {
        float a = 0.5, s = 0.0;
        float2x2 m = float2x2(1.6, 1.2, -1.2, 1.6);
        for (int i = 0; i < 3; i++) { s += a * noise(p); p = m * p; a *= 0.5; }
        return s / 0.875;
    }
    static float easeInOut(float x) { return 0.5 - 0.5 * cos(M_PI_F * x); }

    fragment float4 inkFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float2 asp = float2(u.aspect, 1.0);
        float p = u.progress, t = u.time, dark;
        if (u.mode == 1) {
            float v = length((in.uv - u.bubble) * asp);
            float n = fbm3(in.uv * asp * 1.1 + float2(t * 0.012, -t * 0.009));
            float f = 0.16;
            // The clear area shrinks so the visible part of the desktop falls away evenly over the whole time.
            float r = mix(-f, u.maxFromBubble + f, sqrt(1.0 - easeInOut(p)));
            dark = smoothstep(-f * 0.5, f * 0.5, v - r + (n - 0.5) * 0.05);
        } else {
            float2 q = (in.uv - u.origin) * asp;
            float w1 = fbm3(q * 0.9 + float2(0.0, t * 0.02)), w2 = fbm3(q * 0.9 + float2(5.2, 1.3) - t * 0.02);
            float n = fbm3(q * 1.2 + 0.8 * float2(w1, w2));
            float f = 0.08 + 0.1 * p;
            float r = mix(-0.12, u.maxFromOrigin + 0.24, 1.0 - pow(1.0 - p, 1.6));
            dark = 1.0 - smoothstep(-f, f * 0.4, length(q) - r + (n - 0.5) * 0.12);
        }
        dark = clamp(dark * u.fade, 0.0, 1.0);
        return float4(0.0, 0.0, 0.0, dark);
    }
    """
}
